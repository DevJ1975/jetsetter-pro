// File: Core/Services/CheckInService.swift
//
// Resolves airline check-in URLs using:
//   1. Amadeus Flight Check-In Links API (primary)
//   2. Hardcoded fallback dictionary for 20 major airlines
//
// SETUP: Set your Amadeus client ID and secret below.
// Create a free app at https://developers.amadeus.com

import Foundation
import UserNotifications

// MARK: - Amadeus Configuration

private enum AmadeusConfig {
    // Read directly from the bundle so these statics are safely `nonisolated`
    // and usable from any actor context (CheckInService is an `actor`, and
    // the project defaults to `@MainActor` isolation).
    nonisolated static let clientID: String     = readSecret("API_AMADEUS_CLIENT_ID")
    nonisolated static let clientSecret: String = readSecret("API_AMADEUS_CLIENT_SECRET")
    // Sandbox in Debug, production in Release/TestFlight. Production requires
    // production Amadeus credentials in Config/Secrets.xcconfig.
    #if DEBUG
    nonisolated static let tokenURL     = "https://test.api.amadeus.com/v1/security/oauth2/token"
    nonisolated static let checkInURL   = "https://test.api.amadeus.com/v2/reference-data/urls/checkin-links"
    #else
    nonisolated static let tokenURL     = "https://api.amadeus.com/v1/security/oauth2/token"
    nonisolated static let checkInURL   = "https://api.amadeus.com/v2/reference-data/urls/checkin-links"
    #endif

    nonisolated static var hasCredentials: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }
}

/// Bundle-level secret reader. Mirrors `AppSecrets.value(for:)` but is
/// `nonisolated` so it can be called from any actor context.
private nonisolated func readSecret(_ key: String) -> String {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return "" }
    if trimmed.hasPrefix("YOUR_") || trimmed == "REPLACE_ME" { return "" }
    return trimmed
}

/// Percent-encodes a value for an `application/x-www-form-urlencoded` body.
/// `.urlQueryAllowed` still permits the sub-delimiters `+`, `&`, `=` (and `%`),
/// so a secret containing any of those would corrupt the body — exclude them.
private nonisolated func formURLEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=%")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

// MARK: - CheckInResult

struct CheckInResult {
    let airlineName: String
    let iataCode: String
    let webURL: URL
    let mobileURL: URL?     // Some airlines expose a separate mobile-optimised URL
    let source: CheckInSource
}

enum CheckInSource {
    case amadeus   // Live from Amadeus API
    case fallback  // Hardcoded dictionary
}

// MARK: - CheckInService

/// Resolves airline check-in deep links and schedules check-in-open notifications.
actor CheckInService {

    static let shared = CheckInService()
    private init() {}

    // Cached Amadeus OAuth token and its expiry
    private var amadeusToken: String?
    private var tokenExpiry: Date = .distantPast
    // Coalesces concurrent token fetches so several simultaneous lookups
    // (e.g. a wallet card list resolving multiple airlines) share one POST
    // instead of each issuing a redundant, rate-limited token request.
    private var tokenTask: Task<String, Error>?

    // MARK: - Public API

    /// Returns check-in URL for the given IATA airline code.
    ///
    /// Resolution order:
    ///   1. Amadeus (live) when credentials are configured — persisted on success.
    ///   2. Last persisted Amadeus result for this code (freshest known URL).
    ///   3. Hardcoded fallback dictionary.
    ///   4. Web-search deep link so the UI never dead-ends.
    func checkInResult(for iataCode: String) async -> CheckInResult? {
        let code = iataCode.uppercased()

        // Try Amadeus first when credentials are configured.
        if AmadeusConfig.hasCredentials {
            if let result = await fetchFromAmadeus(iataCode: code) {
                persistAmadeusResult(result)
                return result
            }
        }

        // Prefer the last successful Amadeus URL over a potentially-stale
        // hardcoded entry — it's the freshest known-good link for this code.
        if let cached = persistedAmadeusResult(for: code) {
            return cached
        }

        // Hardcoded dictionary, then a search deep link as a last resort.
        return fallbackResult(for: code) ?? searchFallbackResult(for: code)
    }

    /// Schedules a local notification to fire when the carrier's online
    /// check-in window opens, reminding the user that check-in is now open.
    func scheduleCheckInNotification(
        airlineName: String,
        flightNumber: String,
        departureDate: Date
    ) async {
        // Check-in does not universally open at T-24h — several international
        // carriers open earlier. Use the carrier's known lead time (defaulting
        // to 24h) so the reminder isn't hours late for those airlines.
        let leadHours = checkInLeadHours(forAirlineNamed: airlineName)
        let checkInOpenTime = departureDate.addingTimeInterval(-leadHours * 3_600)
        guard checkInOpenTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Check-in open — \(flightNumber)"
        content.body  = "\(airlineName) check-in is now open. Tap to check in and select your seat."
        content.sound = .default
        content.categoryIdentifier = "CHECK_IN_OPEN"
        content.userInfo = ["flightNumber": flightNumber]

        // Fire at a fixed instant so the reminder stays correct even if the
        // traveler changes timezones between scheduling and departure. A
        // calendar trigger would capture wall-clock components in the current
        // device timezone and misfire after a timezone change.
        let interval = checkInOpenTime.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let id = "checkin_\(flightNumber.uppercased())_\(Int(departureDate.timeIntervalSince1970))"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    /// Cancels a previously scheduled check-in notification.
    func cancelCheckInNotification(flightNumber: String, departureDate: Date) {
        let id = "checkin_\(flightNumber.uppercased())_\(Int(departureDate.timeIntervalSince1970))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Amadeus OAuth + API

    private func fetchAmadeusToken() async throws -> String {
        if let token = amadeusToken, tokenExpiry > Date() { return token }

        // If a fetch is already in flight, await it rather than starting another.
        if let existing = tokenTask {
            return try await existing.value
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let expiresIn: Int
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn   = "expires_in"
            }
        }

        let task = Task { () throws -> String in
            guard let url = URL(string: AmadeusConfig.tokenURL) else { throw URLError(.badURL) }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "grant_type=client_credentials&client_id=\(formURLEncode(AmadeusConfig.clientID))&client_secret=\(formURLEncode(AmadeusConfig.clientSecret))"
            req.httpBody = body.data(using: .utf8)

            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            self.amadeusToken = decoded.accessToken
            self.tokenExpiry  = Date().addingTimeInterval(Double(decoded.expiresIn) - 60)
            return decoded.accessToken
        }
        tokenTask = task
        defer { tokenTask = nil }

        return try await task.value
    }

    private func fetchFromAmadeus(iataCode: String) async -> CheckInResult? {
        do {
            let token = try await fetchAmadeusToken()

            var comps = URLComponents(string: AmadeusConfig.checkInURL)!
            comps.queryItems = [
                URLQueryItem(name: "airlineCode", value: iataCode),
                URLQueryItem(name: "language",    value: "EN-US")
            ]
            guard let url = comps.url else { return nil }

            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }

            // Amadeus response: { "data": [ { "type": "checkin-link", "id": "...", "href": "...", "channel": "Mobile"|"Web"|"All" } ] }
            struct AmadeusLink: Decodable {
                let href: String
                let channel: String
            }
            struct AmadeusResponse: Decodable {
                let data: [AmadeusLink]
            }

            let decoded = try JSONDecoder().decode(AmadeusResponse.self, from: data)
            guard !decoded.data.isEmpty else { return nil }

            let webLink    = decoded.data.first { $0.channel == "Web" || $0.channel == "All" }
            let mobileLink = decoded.data.first { $0.channel == "Mobile" }

            // Some (typically smaller/international) carriers expose only a
            // Mobile link. Prefer the Web/All link, but fall back to the mobile
            // href as the primary URL rather than discarding a valid result.
            guard let primaryHref = (webLink ?? mobileLink)?.href,
                  let webURL = URL(string: primaryHref) else { return nil }
            // Only surface a separate mobile URL when it differs from the primary.
            let mobileURL = mobileLink
                .flatMap { $0.href == primaryHref ? nil : URL(string: $0.href) }

            let name = fallbackAirlines[iataCode]?.name ?? iataCode
            return CheckInResult(
                airlineName: name,
                iataCode: iataCode,
                webURL: webURL,
                mobileURL: mobileURL,
                source: .amadeus
            )
        } catch {
            return nil
        }
    }

    // MARK: - Amadeus Result Persistence

    /// UserDefaults key namespace for the last successful Amadeus result per code.
    private static let persistPrefix = "checkin_amadeus_"

    private struct PersistedResult: Codable {
        let airlineName: String
        let iataCode: String
        let webURLString: String
        let mobileURLString: String?
    }

    private func persistAmadeusResult(_ result: CheckInResult) {
        let record = PersistedResult(
            airlineName: result.airlineName,
            iataCode: result.iataCode,
            webURLString: result.webURL.absoluteString,
            mobileURLString: result.mobileURL?.absoluteString
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistPrefix + result.iataCode)
    }

    private func persistedAmadeusResult(for iataCode: String) -> CheckInResult? {
        guard let data = UserDefaults.standard.data(forKey: Self.persistPrefix + iataCode),
              let record = try? JSONDecoder().decode(PersistedResult.self, from: data),
              let webURL = URL(string: record.webURLString) else { return nil }
        return CheckInResult(
            airlineName: record.airlineName,
            iataCode: record.iataCode,
            webURL: webURL,
            mobileURL: record.mobileURLString.flatMap(URL.init(string:)),
            source: .amadeus
        )
    }

    // MARK: - Fallback Dictionary

    struct FallbackEntry {
        let name: String
        let webURLString: String
        /// Hours before departure that this carrier's online check-in opens.
        /// Check-in does NOT universally open at T-24h: many international
        /// carriers open earlier (Emirates/Qatar/Lufthansa ~48h). Defaults to
        /// 24h via the initializer when a carrier's window is unknown.
        let checkInLeadHours: Double

        init(name: String, webURLString: String, checkInLeadHours: Double = 24) {
            self.name = name
            self.webURLString = webURLString
            self.checkInLeadHours = checkInLeadHours
        }
    }

    /// Hardcoded check-in URLs for the top 20 US and international airlines.
    /// Updated April 2026 — verify these periodically as airlines may change URLs.
    private let fallbackAirlines: [String: FallbackEntry] = [
        // US Carriers — nearly all open at T-24h.
        "UA": FallbackEntry(name: "United Airlines",        webURLString: "https://www.united.com/en/us/checkin"),
        "DL": FallbackEntry(name: "Delta Air Lines",        webURLString: "https://www.delta.com/us/en/check-in/overview"),
        "AA": FallbackEntry(name: "American Airlines",      webURLString: "https://www.aa.com/checkin/viewCheckinPage"),
        "WN": FallbackEntry(name: "Southwest Airlines",     webURLString: "https://www.southwest.com/air/check-in/"),
        "B6": FallbackEntry(name: "JetBlue",                webURLString: "https://checkin.jetblue.com/"),
        "AS": FallbackEntry(name: "Alaska Airlines",        webURLString: "https://www.alaskaair.com/checkin"),
        "NK": FallbackEntry(name: "Spirit Airlines",        webURLString: "https://www.spirit.com/CheckIn"),
        "F9": FallbackEntry(name: "Frontier Airlines",      webURLString: "https://www.flyfrontier.com/travel/travel-info/check-in/"),
        "HA": FallbackEntry(name: "Hawaiian Airlines",      webURLString: "https://www.hawaiianairlines.com/my-trips/check-in"),
        "G4": FallbackEntry(name: "Allegiant Air",          webURLString: "https://www.allegiantair.com/online-check-in"),
        // International Carriers — several open earlier than 24h.
        "BA": FallbackEntry(name: "British Airways",        webURLString: "https://www.britishairways.com/travel/olcilandingpageauthreq/public/en_gb"),
        "AF": FallbackEntry(name: "Air France",             webURLString: "https://checkin.airfrance.com/",                       checkInLeadHours: 30),
        "LH": FallbackEntry(name: "Lufthansa",              webURLString: "https://www.lufthansa.com/us/en/online-check-in",       checkInLeadHours: 23),
        "EK": FallbackEntry(name: "Emirates",               webURLString: "https://www.emirates.com/english/manage/online-check-in/", checkInLeadHours: 48),
        "QR": FallbackEntry(name: "Qatar Airways",          webURLString: "https://www.qatarairways.com/en/check-in.html",         checkInLeadHours: 48),
        "AC": FallbackEntry(name: "Air Canada",             webURLString: "https://www.aircanada.com/us/en/aco/home/fly/check-in.html"),
        "WS": FallbackEntry(name: "WestJet",                webURLString: "https://www.westjet.com/en-ca/check-in"),
        "LA": FallbackEntry(name: "LATAM Airlines",         webURLString: "https://www.latamairlines.com/us/en/experience/prepare-your-trip/check-in", checkInLeadHours: 48),
        "AV": FallbackEntry(name: "Avianca",                webURLString: "https://www.avianca.com/us/en/prepare-your-trip/at-the-airport/check-in/"),
        "KL": FallbackEntry(name: "KLM Royal Dutch Airlines", webURLString: "https://www.klm.com/us/en/travel-information/check-in/online-check-in", checkInLeadHours: 30)
    ]

    /// Lead hours before departure that the named airline's check-in opens.
    /// Looked up by display name (the scheduling API only receives the name,
    /// not the IATA code). Defaults to 24h when the carrier is unknown.
    private func checkInLeadHours(forAirlineNamed name: String) -> Double {
        let target = name.lowercased()
        return fallbackAirlines.values
            .first { $0.name.lowercased() == target }?
            .checkInLeadHours ?? 24
    }

    private func fallbackResult(for iataCode: String) -> CheckInResult? {
        guard let entry = fallbackAirlines[iataCode],
              let url = URL(string: entry.webURLString) else { return nil }
        return CheckInResult(
            airlineName: entry.name,
            iataCode: iataCode,
            webURL: url,
            mobileURL: nil,
            source: .fallback
        )
    }

    /// Last-resort result for carriers outside the fallback dictionary when
    /// Amadeus is unavailable. Rather than dead-ending the UI at "unavailable",
    /// hand the user an actionable web search for the airline's check-in page.
    private func searchFallbackResult(for iataCode: String) -> CheckInResult? {
        let query = "\(iataCode) airline online check in"
        var comps = URLComponents(string: "https://www.google.com/search")
        comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = comps?.url else { return nil }
        return CheckInResult(
            airlineName: iataCode,
            iataCode: iataCode,
            webURL: url,
            mobileURL: nil,
            source: .fallback
        )
    }
}
