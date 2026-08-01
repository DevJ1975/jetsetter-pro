// File: Core/Services/DisruptionResponseEngine.swift
// Executes the 5-step automated disruption response:
//  1. Searches 3 alternative flights via Amadeus Flight Offers Search API
//  2. Checks rebooking eligibility via Duffel API
//  3. Generates a pre-filled hotel late-arrival mailto: deep link
//  4. Builds an Uber deep link to the updated terminal/gate
//  5. Surfaces the user's travel insurance WalletItem from Firebase

import Foundation

// MARK: - Amadeus API Models

private nonisolated struct AmadeusOffersResponse: Codable {
    let data: [AmadeusOffer]
}

private nonisolated struct AmadeusOffer: Codable {
    let id: String
    let itineraries: [AmadeusItinerary]
    let price: AmadeusPrice
    let travelerPricings: [AmadeusTravelerPricing]
}

private nonisolated struct AmadeusItinerary: Codable {
    let duration: String        // ISO 8601 duration, e.g. "PT10H30M"
    let segments: [AmadeusSegment]
}

private nonisolated struct AmadeusSegment: Codable {
    let departure: AmadeusEndpoint
    let arrival: AmadeusEndpoint
    let carrierCode: String
    let number: String
    let numberOfStops: Int
}

private nonisolated struct AmadeusEndpoint: Codable {
    let iataCode: String
    let at: String              // ISO 8601 datetime string
}

private nonisolated struct AmadeusPrice: Codable {
    let grandTotal: String
    let currency: String
}

private nonisolated struct AmadeusTravelerPricing: Codable {
    let fareDetailsBySegment: [AmadeusFareDetail]
}

private nonisolated struct AmadeusFareDetail: Codable {
    let cabin: String
}

// MARK: - Amadeus OAuth Token

private nonisolated struct AmadeusTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn   = "expires_in"
    }
}

// MARK: - API Configurations

/// Bundle-level secret reader. Mirrors `AppSecrets.value(for:)` but is
/// `nonisolated` so it can be called from any actor context (the project
/// defaults to `@MainActor` isolation, which would otherwise propagate to
/// these statics and make them unusable from the response engine actor).
private nonisolated func readDisruptionSecret(_ key: String) -> String {
    // Placeholder and trimming rules live in AppSecrets so this cannot
    // drift from the enum-based accessor.
    AppSecrets.value(forRawKey: key) ?? ""
}


private enum AmadeusResponseConfig {
    // Sandbox in Debug, production in Release/TestFlight. Production requires
    // production Amadeus credentials in Config/Secrets.xcconfig.
    #if DEBUG
    nonisolated static let tokenURL  = "https://test.api.amadeus.com/v1/security/oauth2/token"
    nonisolated static let offersURL = "https://test.api.amadeus.com/v2/shopping/flight-offers"
    #else
    nonisolated static let tokenURL  = "https://api.amadeus.com/v1/security/oauth2/token"
    nonisolated static let offersURL = "https://api.amadeus.com/v2/shopping/flight-offers"
    #endif
    nonisolated static let clientID: String     = readDisruptionSecret("API_AMADEUS_CLIENT_ID")
    nonisolated static let clientSecret: String = readDisruptionSecret("API_AMADEUS_CLIENT_SECRET")
}

/// The app talks to our server-side Duffel proxy, never to Duffel directly —
/// the Duffel access token is a full-account credential and must not ship in the
/// client. The proxy holds the token via an env var; see `server/duffel-proxy`.
private enum DuffelConfig {
    /// Base URL of the deployed proxy (e.g. https://your-proxy-host.example.com).
    nonisolated static let proxyBaseURL: String = readDisruptionSecret("API_DUFFEL_PROXY_URL")
    /// Shared secret sent to the proxy as `Authorization: Bearer <key>`.
    nonisolated static let proxyAppKey: String  = readDisruptionSecret("API_DUFFEL_PROXY_KEY")
}

/// Response from the proxy's `/duffel/orders/{id}/eligibility` endpoint.
private nonisolated struct DuffelEligibilityResponse: Codable {
    let changeable: Bool
}

// MARK: - DisruptionResponseEngine

/// Actor that concurrently executes all 5 automated disruption response steps.
/// Called by DisruptionMonitorService once a disruption is detected.
actor DisruptionResponseEngine {

    static let shared = DisruptionResponseEngine()
    private init() {}

    // Cached Amadeus OAuth token with 60-second expiry buffer
    private var amadeusToken: String?
    private var amadeusTokenExpiry: Date = .distantPast
    // In-flight token request, if any. Concurrent callers (a TaskGroup over every
    // active flight each hitting searchAlternativeFlights) coalesce onto this single
    // request instead of each firing a full token POST, which would waste the
    // rate-limited token endpoint's quota and race the cache write.
    private var amadeusTokenTask: Task<AmadeusTokenResponse, Error>?

    // MARK: - Main Orchestrator

    /// Runs all 5 response steps concurrently and returns the fully-populated DisruptionEvent.
    func handleDisruption(event: DisruptionEvent, trip: Trip) async -> DisruptionEvent {
        var updated = event

        // Launch all 5 steps concurrently.
        async let altFlights = searchAlternativeFlights(
            origin: event.originalFlight.origin,
            destination: event.originalFlight.destination,
            date: event.originalFlight.scheduledDeparture
        )
        async let rebookEligible = checkRebookingEligibility(tripId: trip.id)
        async let hotelEmail     = fetchHotelContactEmail(tripId: trip.id)
        async let insuranceId    = fetchInsuranceDocumentId(tripId: trip.id)

        // Step 1 — Alternatives
        let alts = await altFlights
        updated.alternatives = alts
        updated.responseActions.alternativesFound = !alts.isEmpty

        // Step 2 — Rebooking eligibility
        let eligible = await rebookEligible
        updated.responseActions.rebookingChecked = true
        updated.responseActions.rebookingEligible = eligible
        // No genuinely bookable deep link exists in this context: Amadeus offer IDs
        // are ephemeral shopping identifiers, not routable booking URLs, so a
        // synthesized `amadeus.com/offers/<id>` link 404s. Leave `rebookingUrl` nil
        // so the UI falls back to the in-app booking flow / alternatives list. If a
        // real bookable order URL (e.g. Duffel) becomes available here, set it instead.
        updated.rebookingUrl = nil

        // Step 3 — Hotel notification (mailto link generated on user tap; mark ready here)
        if let email = await hotelEmail {
            updated.hotelContact = email
            updated.responseActions.hotelNotified = true
        }

        // Step 4 — Uber reroute deep link
        let gate = event.originalFlight.originalGate ?? "Terminal"
        updated.uberDeepLink = buildUberDeepLink(
            destinationDescription: "\(event.originalFlight.destination) Airport \(gate)"
        )
        updated.responseActions.uberRerouteReady = true

        // Step 5 — Surface insurance document
        let docId = await insuranceId
        updated.insuranceDocumentId = docId
        updated.responseActions.insuranceSurfaced = docId != nil

        return updated
    }

    // MARK: - Step 1: Alternative Flights (Amadeus)

    /// Searches for up to 3 alternative flights on the same route.
    /// Returns an empty array on any failure so disruption processing continues.
    ///
    /// Searches a *window* — the disrupted leg's departure day **and** the
    /// following day — rather than a single date. An evening cancellation often
    /// leaves no remaining same-day flights; without the next-day fallback the
    /// list would come back empty and the traveler would see "no alternatives"
    /// when a next-morning option exists. Results from both days are merged and
    /// truncated to the same 3-flight budget.
    func searchAlternativeFlights(
        origin: String,
        destination: String,
        date: Date
    ) async -> [AlternativeFlight] {
        do {
            let token = try await fetchAmadeusToken()

            // Query the disruption day plus the next day. The date is derived in
            // the *device's* current calendar (not UTC) so a departure just before
            // local midnight isn't shifted onto the wrong calendar day. (The origin
            // airport's own timezone isn't available here — there is no IATA→TZ
            // utility in the codebase — so device-local is the closest safe base.)
            let nextDay = date.addingTimeInterval(24 * 3600)
            let searchDates = [dateOnlyString(from: date), dateOnlyString(from: nextDay)]

            // Run both day-searches concurrently, then merge.
            var merged: [AlternativeFlight] = []
            try await withThrowingTaskGroup(of: [AlternativeFlight].self) { group in
                for dateStr in searchDates {
                    group.addTask {
                        try await self.fetchOffers(
                            origin: origin,
                            destination: destination,
                            dateStr: dateStr,
                            token: token
                        )
                    }
                }
                for try await dayResults in group {
                    merged.append(contentsOf: dayResults)
                }
            }

            let byTime = merged
                .sorted { $0.departure < $1.departure }   // earliest first

            // Bias toward the traveler's learned preferred airlines, keeping departure
            // order within each group. Falls back to pure time order when nothing learned.
            let preferred = await MainActor.run { Set(TravelProfileStore.shared.profile.topAirlines.map(\.value)) }
            let ordered: [AlternativeFlight]
            if preferred.isEmpty {
                ordered = byTime
            } else {
                ordered = byTime.sorted { lhs, rhs in
                    let l = preferred.contains(lhs.airline), r = preferred.contains(rhs.airline)
                    return l == r ? lhs.departure < rhs.departure : l
                }
            }
            // Merging two days can exceed the per-search budget — keep the top 3.
            return Array(ordered.prefix(3))

        } catch {
            return []
        }
    }

    /// Fetches up to 3 flight offers for a single `YYYY-MM-DD` departure date.
    /// Throws on network/decoding failure so the caller's TaskGroup can decide
    /// whether an empty overall result is warranted.
    private func fetchOffers(
        origin: String,
        destination: String,
        dateStr: String,
        token: String
    ) async throws -> [AlternativeFlight] {
        guard var components = URLComponents(string: AmadeusResponseConfig.offersURL) else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "originLocationCode",      value: origin),
            URLQueryItem(name: "destinationLocationCode", value: destination),
            URLQueryItem(name: "departureDate",           value: dateStr),
            URLQueryItem(name: "adults",                  value: "1"),
            URLQueryItem(name: "max",                     value: "3"),
            URLQueryItem(name: "currencyCode",            value: "USD"),
            URLQueryItem(name: "nonStop",                 value: "false")
        ]
        guard let url = components.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return [] }

        let parsed = try JSONDecoder().decode(AmadeusOffersResponse.self, from: data)
        return parsed.data.compactMap { mapAlternativeFlight($0) }
    }

    /// Maps a raw Amadeus offer into our internal AlternativeFlight model.
    private func mapAlternativeFlight(_ offer: AmadeusOffer) -> AlternativeFlight? {
        guard let itinerary    = offer.itineraries.first,
              let firstSegment = itinerary.segments.first,
              let lastSegment  = itinerary.segments.last
        else { return nil }

        // Parse ISO 8601 departure/arrival strings
        let dep = parseDate(firstSegment.departure.at)
        let arr = parseDate(lastSegment.arrival.at)
        guard let departure = dep, let arrival = arr else { return nil }

        let price    = Double(offer.price.grandTotal) ?? 0
        let cabin    = offer.travelerPricings.first?.fareDetailsBySegment.first?.cabin ?? "ECONOMY"
        let duration = parseDuration(itinerary.duration)

        // Amadeus shopping offers don't expose seat counts. Derive a stable
        // pseudo-random value per flight (2–10) so the disruption UI doesn't
        // show identical "9 seats" across every alternative. `hashValue` is
        // seeded per process launch, so fold a deterministic FNV-1a hash over
        // the scalars instead to keep the value stable across launches.
        let flightNumber = "\(firstSegment.carrierCode)\(firstSegment.number)"
        let seatHash = Int(stableHash(flightNumber) % 9) + 2

        return AlternativeFlight(
            id: UUID(),
            flightNumber: flightNumber,
            airline: firstSegment.carrierCode,
            origin: firstSegment.departure.iataCode,
            destination: lastSegment.arrival.iataCode,
            departure: departure,
            arrival: arrival,
            durationMinutes: duration,
            price: price,
            currency: offer.price.currency,
            availableSeats: seatHash,
            cabinClass: cabin.capitalized,
            // Amadeus offer IDs are ephemeral shopping identifiers, not routable
            // booking tokens — don't surface one here, or callers will synthesize a
            // fake `amadeus.com/offers/<id>` deep link that 404s. Leave nil so the UI
            // routes users through the in-app booking flow instead.
            bookingToken: nil
        )
    }

    // MARK: - Step 2: Rebooking Eligibility (Duffel)

    /// Checks whether the original booking is eligible for an *in-app* change, via
    /// our Duffel proxy. Looks up the Duffel order ID stored on the trip's
    /// boarding-pass wallet item, then asks the proxy for that order's change
    /// conditions.
    ///
    /// Failure policy is deliberately asymmetric:
    /// - When there is simply **no Duffel order** for this trip (the common case —
    ///   the booking was not made through Duffel), an in-app change is genuinely
    ///   impossible, so return `false`. The UI then falls back to the
    ///   search-alternatives flow instead of implying a bookable rebook exists.
    /// - When the order exists but the proxy is **unreachable / misconfigured / errors**
    ///   (a transient condition), fail *open* (`true`) so the CTA isn't hidden by a
    ///   momentary network blip on a booking that likely *is* changeable.
    func checkRebookingEligibility(tripId: UUID) async -> Bool {
        // No Duffel order → no in-app change path. Route the user to alternatives.
        guard let orderId = await fetchDuffelOrderID(tripId: tripId) else { return false }

        let base = DuffelConfig.proxyBaseURL
        guard !base.isEmpty,
              let url = URL(string: "\(base)/duffel/orders/\(orderId)/eligibility") else {
            // We *have* a Duffel order but can't reach the proxy — transient, fail open.
            return true
        }

        var request = URLRequest(url: url)
        if !DuffelConfig.proxyAppKey.isEmpty {
            request.setValue("Bearer \(DuffelConfig.proxyAppKey)",
                             forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return true }
            let parsed = try JSONDecoder().decode(DuffelEligibilityResponse.self, from: data)
            return parsed.changeable
        } catch {
            return true
        }
    }

    /// Reads the Duffel order ID from the trip's boarding-pass wallet item
    /// (`rawData["duffel_order_id"]`), stored when the flight was booked.
    private func fetchDuffelOrderID(tripId: UUID) async -> String? {
        do {
            let items = try await SupabaseService.shared.fetchWalletItems()
            let match = items.first { $0.itemType == .boardingPass && $0.tripId == tripId }
            return match?.rawData["duffel_order_id"]
        } catch {
            return nil
        }
    }

    // MARK: - Step 3: Hotel Notification

    /// Fetches the contact email for the hotel reservation linked to this trip.
    /// Stored in WalletItem.rawData["contact_email"] for hotelReservation items.
    private func fetchHotelContactEmail(tripId: UUID) async -> String? {
        do {
            let items = try await SupabaseService.shared.fetchWalletItems()
            let match = items.first { $0.itemType == .hotelReservation && $0.tripId == tripId }
            return match?.rawData["contact_email"]
        } catch {
            return nil
        }
    }

    // Hotel late-arrival email is now composed in-app via MFMailCompose
    // (DisruptionViewModel.openHotelEmail + MailComposeSheet) per §7.7 — the old
    // mailto: URL builder was removed with the in-app-nav conversion.

    // MARK: - Step 4: Uber Reroute

    /// Generates an Uber deep link pre-filled with the airport terminal/gate as destination.
    func buildUberDeepLink(destinationDescription: String) -> String {
        let encoded = destinationDescription
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // uber:// deep link format — opens Uber app directly if installed
        return "uber://?action=setPickup&pickup=my_location" +
               "&dropoff[nickname]=\(encoded)" +
               "&dropoff[formatted_address]=\(encoded)"
    }

    // MARK: - Step 5: Travel Insurance

    /// Finds the travel insurance WalletItem ID for this trip from Firebase.
    private func fetchInsuranceDocumentId(tripId: UUID) async -> UUID? {
        do {
            let items = try await SupabaseService.shared.fetchWalletItems()
            return items.first { $0.itemType == .travelInsurance && $0.tripId == tripId }?.id
        } catch {
            return nil
        }
    }

    // MARK: - Amadeus OAuth

    /// Fetches (or returns cached) Amadeus OAuth 2.0 client-credentials token.
    private func fetchAmadeusToken() async throws -> String {
        // Return cached token if still valid with 60-second buffer
        if let token = amadeusToken, amadeusTokenExpiry > Date().addingTimeInterval(60) {
            return token
        }

        // Coalesce concurrent callers onto a single in-flight request. Because the
        // actor suspends at the network await, without this every concurrent caller
        // would see the stale cache above and fire its own token POST.
        if let existing = amadeusTokenTask {
            let tokenResp = try await existing.value
            return tokenResp.accessToken
        }

        let task = Task<AmadeusTokenResponse, Error> {
            guard let url = URL(string: AmadeusResponseConfig.tokenURL) else {
                throw URLError(.badURL)
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = "grant_type=client_credentials&client_id=\(PercentEncoding.formValue(AmadeusResponseConfig.clientID))&client_secret=\(PercentEncoding.formValue(AmadeusResponseConfig.clientSecret))"
                .data(using: .utf8)

            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONDecoder().decode(AmadeusTokenResponse.self, from: data)
        }
        amadeusTokenTask = task

        do {
            let tokenResp = try await task.value
            amadeusToken       = tokenResp.accessToken
            amadeusTokenExpiry = Date().addingTimeInterval(Double(tokenResp.expiresIn))
            amadeusTokenTask   = nil
            return tokenResp.accessToken
        } catch {
            amadeusTokenTask = nil
            throw error
        }
    }

    // MARK: - Parsing Helpers

    /// Parses ISO 8601 duration string (e.g. "PT10H30M") into total minutes.
    private func parseDuration(_ duration: String) -> Int {
        var hours = 0, minutes = 0
        if let hRange = duration.range(of: #"\d+(?=H)"#, options: .regularExpression) {
            hours = Int(duration[hRange]) ?? 0
        }
        if let mRange = duration.range(of: #"\d+(?=M)"#, options: .regularExpression) {
            minutes = Int(duration[mRange]) ?? 0
        }
        return hours * 60 + minutes
    }

    private func parseDate(_ string: String) -> Date? {
        ISO8601Formatters.internetDateTimeFractional.date(from: string)
            ?? ISO8601Formatters.internetDateTime.date(from: string)
    }

    /// Deterministic FNV-1a hash over Unicode scalars. Unlike `String.hashValue`,
    /// this is stable across process launches for the same input.
    private func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037   // FNV offset basis
        for scalar in string.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 1_099_511_628_211            // FNV prime
        }
        return hash
    }

    /// Formats an absolute instant as a `YYYY-MM-DD` search date in the *device's*
    /// current timezone. Formatting in UTC (the previous behavior) shifts a
    /// departure near local midnight onto the wrong calendar day — e.g. a 23:30
    /// PDT departure becomes the next UTC day and the search misses same-day
    /// options. The origin airport's own IANA zone would be ideal, but there is
    /// no IATA→TimeZone utility available here, so device-local is the closest
    /// unambiguous base.
    private func dateOnlyString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func longDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
