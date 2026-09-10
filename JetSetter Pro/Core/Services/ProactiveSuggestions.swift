// File: Core/Services/ProactiveSuggestions.swift
//
// Decides when the app should speak first. Evaluates trip state + time-of-day
// and returns the highest-priority suggestion, each with the screen it opens
// and (where useful) the phrase to ask Siri. Each suggestion has a dismissal
// key so the same nudge doesn't reappear after the user swipes it away.

import Foundation

// MARK: - Suggestion

struct TravelSuggestion: Identifiable, Equatable {
    let id: UUID
    let kind: Kind
    let title: String
    let body: String
    /// Where "Open" takes the traveler.
    let action: AppRouter.Destination
    /// Optional Siri phrase that does the same thing hands-free.
    let siriPhrase: String?
    let dismissalKey: String        // Bucket for de-dup

    enum Kind: String, CaseIterable {
        case checkInWindow      // < 24h to next flight, not yet checked in
        case seatPreferenceNudge // check-in window + a learned seat preference
        case preferredCabinNudge // check-in window + a learned premium-cabin preference
        case budgetPacingNudge  // active trip spending above the learned typical
        case tierAtRisk         // Loyalty tier expires within 7 days
        case rideToAirport      // < 12h to next flight, no Uber pre-booked
        case rideOnLanding      // Flight arriving soon — offer a ride timed to baggage
        case packingNudge       // 14-28 days out, no packing list
        case visaCheck          // 7 days out, eVisa or visaRequired
        case weatherWatch       // 3 days out, rain in forecast
        case dailyBriefing      // First open of the day during active trip
        case welcomeHome        // < 24h after trip ended

        var systemImage: String {
            switch self {
            case .checkInWindow:   return "checkmark.seal.fill"
            case .seatPreferenceNudge: return "chair.fill"
            case .preferredCabinNudge: return "star.circle.fill"
            case .budgetPacingNudge: return "creditcard.trianglebadge.exclamationmark"
            case .tierAtRisk:      return "crown.fill"
            case .rideToAirport:   return "car.fill"
            case .rideOnLanding:   return "car.fill"
            case .packingNudge:    return "checklist"
            case .visaCheck:       return "doc.text.fill"
            case .weatherWatch:    return "cloud.rain.fill"
            case .dailyBriefing:   return "sun.max.fill"
            case .welcomeHome:     return "book.pages.fill"
            }
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class ProactiveSuggestions {

    static let shared = ProactiveSuggestions()
    private init() {}

    private let dismissalsKey = "iris_dismissed_suggestions"

    /// Returns the highest-priority suggestion the user hasn't dismissed.
    /// Call from HomeViewModel on every load.
    func evaluate(now: Date = Date()) -> TravelSuggestion? {
        evaluateAll(now: now).first
    }

    /// Returns ALL active suggestions in priority order, filtered by the
    /// dismissal set. HomeViewModel uses this to drive a "+N more" badge.
    func evaluateAll(now: Date = Date()) -> [TravelSuggestion] {
        let trips = loadTrips()
        let dismissals = dismissedKeys()

        // Priority order: checkInWindow > tierAtRisk > rideToAirport >
        // packingNudge > visaCheck > weatherWatch > dailyBriefing > welcomeHome.
        let candidates: [TravelSuggestion?] = [
            evaluateCheckInWindow(trips: trips, now: now),
            evaluateSeatPreferenceNudge(trips: trips, now: now),
            evaluatePreferredCabinNudge(trips: trips, now: now),
            evaluateTierAtRisk(now: now),
            evaluateRideToAirport(trips: trips, now: now),
            evaluateRideOnLanding(trips: trips, now: now),
            evaluatePackingNudge(trips: trips, now: now),
            evaluateVisaCheck(trips: trips, now: now),
            evaluateWeatherWatch(trips: trips, now: now),
            evaluateDailyBriefing(trips: trips, now: now),
            evaluateBudgetPacingNudge(trips: trips, now: now),
            evaluateWelcomeHome(trips: trips, now: now)
        ]

        let surfaced = candidates
            .compactMap { $0 }
            .filter { !dismissals.contains($0.dismissalKey) }
            // Feedback loop: stop surfacing an OPTIONAL learning nudge the user keeps
            // waving away. Operational/safety nudges (check-in, ride, visa…) are never
            // suppressed this way — only the profile-driven "smart" suggestions.
            // Bidirectional + time-windowed: back off only after repeated *recent*
            // dismissals with no recent acceptance, so a welcomed nudge stays alive and
            // an old dismissal (before habits changed) no longer silences it forever.
            .filter { s in
                guard Self.suppressibleKinds.contains(s.kind) else { return true }
                let fb = TravelProfileStore.shared.suggestionFeedback(forKind: s.kind.rawValue)
                return !(fb.dismisses >= 3 && fb.accepts == 0)
            }

        // Count each unique suggestion as one impression (deduped by dismissal key,
        // so repeated Home reloads don't inflate it) to power acceptance-rate metrics.
        for s in surfaced {
            SuggestionMetricsStore.shared.recordImpression(kind: s.kind.rawValue, dedupKey: s.dismissalKey)
        }
        return surfaced
    }

    /// Profile-driven nudges that should back off after repeated dismissals.
    private static let suppressibleKinds: Set<TravelSuggestion.Kind> =
        [.seatPreferenceNudge, .preferredCabinNudge, .budgetPacingNudge]

    // MARK: - Triggers

    /// Fires when the next flight departs in < 24h and the user hasn't
    /// marked it as checked-in yet. One-shot via dismissalKey.
    private func evaluateCheckInWindow(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let (_, item) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 0, hours < 24 else { return nil }

        let parsed = extractFlightNumber(from: item.title)
        let flightNumber = parsed ?? "your flight"
        guard !CheckInStateStore.isCheckedIn(
            flightNumber: parsed ?? TravelStore.unparsedFlightToken,
            departure: item.startDate
        ) else { return nil }

        let hoursText = max(1, Int(hours.rounded()))
        return TravelSuggestion(
            id: UUID(),
            kind: .checkInWindow,
            title: "Check in to \(flightNumber)?",
            body: "Your flight leaves in \(hoursText) hour\(hoursText == 1 ? "" : "s"). Open the airline's check-in and save your pass.",
            action: .checkIn,
            siriPhrase: "Check in for my flight in JetSetter Pro",
            dismissalKey: "checkin_\(flightNumber)_\(Int(item.startDate.timeIntervalSince1970))"
        )
    }

    /// Fires within the check-in window when the app has learned a confident seat
    /// preference — offering to apply it. This is the first profile-driven,
    /// anticipatory nudge (the learning layer feeding the proactive surface).
    private func evaluateSeatPreferenceNudge(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let seat = TravelProfileStore.shared.profile.typicalSeat,
              seat.column != .unknown,
              seat.confidence >= 0.6,
              seat.sampleSize >= 2 else { return nil }

        guard let (_, item) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 0, hours < 36 else { return nil }

        let flightNumber = extractFlightNumber(from: item.title) ?? "your flight"
        return TravelSuggestion(
            id: UUID(),
            kind: .seatPreferenceNudge,
            title: "Same seat as usual on \(flightNumber)?",
            body: "You usually fly \(seat.displayName). Check for one when you check in for \(flightNumber).",
            action: .checkIn,
            siriPhrase: nil,
            dismissalKey: "seatpref_\(flightNumber)_\(Int(item.startDate.timeIntervalSince1970))"
        )
    }

    /// Within the check-in window, if the traveler usually flies a premium cabin,
    /// offers to look for an upgrade/award seat. Profile-driven anticipation.
    private func evaluatePreferredCabinNudge(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let raw = TravelProfileStore.shared.profile.preferredCabin else { return nil }
        let cabin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let premium = ["business", "first", "premium"]
        guard premium.contains(where: { cabin.lowercased().contains($0) }) else { return nil }
        guard let (_, item) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 0, hours < 36 else { return nil }

        let flightNumber = extractFlightNumber(from: item.title) ?? "your flight"
        return TravelSuggestion(
            id: UUID(),
            kind: .preferredCabinNudge,
            title: "Check \(cabin) options on \(flightNumber)?",
            body: "You usually fly \(cabin). Look for an upgrade or award seat while checking in for \(flightNumber).",
            action: .checkIn,
            siriPhrase: nil,
            dismissalKey: "cabin_\(flightNumber)_\(Int(item.startDate.timeIntervalSince1970))"
        )
    }

    /// During an active trip, flags a spending category that is pacing well above the
    /// traveler's learned typical average for that category.
    private func evaluateBudgetPacingNudge(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let trip = trips.first(where: { $0.startDate <= now && now <= $0.endDate }) else { return nil }
        let learned = TravelProfileStore.shared.profile.spendByCategory
        guard !learned.isEmpty else { return nil }

        // Exclude mileage (reimbursement bookkeeping, not a spend preference) to match
        // how learned averages are computed in TravelProfileEngine.
        let tripExpenses = loadExpenses().filter {
            $0.date >= trip.startDate && $0.date <= now && $0.category != .mileage
        }
        guard !tripExpenses.isEmpty else { return nil }

        let groups = Dictionary(grouping: tripExpenses) { "\($0.category.displayName)|\($0.currency)" }
        var worst: (category: String, currency: String, tripAvg: Double, learnedAvg: Double)?
        for (key, items) in groups {
            // Need ≥2 charges THIS trip to form a trip average, and the learned
            // baseline must itself rest on ≥3 charges — otherwise we'd be comparing
            // an average against a 1–2 sample "typical", a classic false-positive.
            guard items.count >= 2,
                  let stat = learned.first(where: { "\($0.category)|\($0.currency)" == key }),
                  stat.count >= 3 else { continue }
            // Median trip charge resists a single splurge tipping the alert.
            let tripAvg = TravelProfileEngine.median(items.map(\.amount))
            guard stat.average > 0, tripAvg > stat.average * 1.3 else { continue }
            // Compare candidates by the *ratio* over the learned baseline, not the raw
            // delta: deltas live in per-group currencies (a 5000 JPY overage vs a 20 USD
            // overage), so the larger nominal number would win regardless of real
            // magnitude. The ratio is currency-independent, so the category that's truly
            // running the hottest surfaces.
            let ratio = tripAvg / stat.average
            let worstRatio = worst.map { $0.tripAvg / $0.learnedAvg } ?? 0
            if worst == nil || ratio > worstRatio {
                worst = (stat.category, stat.currency, tripAvg, stat.average)
            }
        }
        guard let w = worst else { return nil }

        let dayKey = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        return TravelSuggestion(
            id: UUID(),
            kind: .budgetPacingNudge,
            title: "\(w.category) spend is running high",
            body: "You're averaging ~\(Int(w.tripAvg.rounded())) \(w.currency) per \(w.category.lowercased()) charge this trip, above your usual ~\(Int(w.learnedAvg.rounded())).",
            action: .expenses,
            siriPhrase: nil,
            dismissalKey: "budget_\(trip.id.uuidString)_\(w.category)_\(dayKey)"
        )
    }

    /// Fires when any saved loyalty account's tier expiration is within 7 days.
    private func evaluateTierAtRisk(now: Date) -> TravelSuggestion? {
        let accounts = loadLoyaltyAccounts()
        let cal = Calendar.current

        guard let atRisk = accounts.first(where: { acct in
            guard let expiry = acct.tierExpiration else { return false }
            let days = cal.dateComponents([.day], from: now, to: expiry).day ?? Int.max
            return days >= 0 && days <= 7
        }) else { return nil }

        let programName = LoyaltyProgramCatalog.find(id: atRisk.programID)?.name ?? atRisk.programID
        // Relative, unambiguous phrasing: "today"/"tomorrow"/"in N days" plus the
        // absolute date, so "Monday" can't be read as this week's Monday and the
        // urgency reads clearly.
        let expiryLabel: String = {
            guard let date = atRisk.tierExpiration else { return "soon" }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                          to: cal.startOfDay(for: date)).day ?? 0
            let df = DateFormatter(); df.dateFormat = "EEE, MMM d"
            let dateStr = df.string(from: date)
            switch days {
            case ..<0:  return "soon"
            case 0:     return "today (\(dateStr))"
            case 1:     return "tomorrow (\(dateStr))"
            default:    return "in \(days) days (\(dateStr))"
            }
        }()
        let expiryKey = atRisk.tierExpiration.map { Int($0.timeIntervalSince1970) } ?? 0

        return TravelSuggestion(
            id: UUID(),
            kind: .tierAtRisk,
            title: "\(programName) \(atRisk.tier) at risk",
            body: "Your \(programName) \(atRisk.tier) status expires \(expiryLabel). Check the program's requalification options.",
            action: .more,
            siriPhrase: nil,
            dismissalKey: "tier_at_risk_\(atRisk.programID)_\(expiryKey)"
        )
    }

    /// Fires when the next flight departs in < 12h and the user hasn't
    /// flagged an Uber as already booked (uber_booked UserDefaults flag).
    private func evaluateRideToAirport(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let (_, item) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 0, hours < 12 else { return nil }

        // Rest the nudge for 12h after the traveler opened a ride app (the old
        // boolean "uber_booked" never expired, so one tap silenced every trip).
        if GroundTransportViewModel.recentlyOpenedRide { return nil }

        let origin = (item.location ?? "")
            .components(separatedBy: " → ")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? "the airport"

        return TravelSuggestion(
            id: UUID(),
            kind: .rideToAirport,
            title: "Pre-book your ride to \(origin)?",
            body: "Your flight leaves in under \(Int(hours.rounded(.up))) hours. Check the drive and open Uber or Lyft with the route filled in.",
            action: .groundTransport,
            siriPhrase: nil,
            dismissalKey: "ride_to_airport_\(Int(item.startDate.timeIntervalSince1970))"
        )
    }

    /// Fires when a flight is arriving soon (within ~90 min, or just landed) and
    /// the traveler hasn't lined up a destination ride. Offers an Uber/Lyft timed
    /// to when the checked bag should reach the carousel.
    private func evaluateRideOnLanding(trips: [Trip], now: Date) -> TravelSuggestion? {
        let flights = trips.flatMap { $0.items.filter { $0.type == .flight } }
        guard let item = flights.first(where: { item in
            guard let arrival = item.endDate else { return false }
            let minutesToArrival = arrival.timeIntervalSince(now) / 60
            return minutesToArrival <= 90 && minutesToArrival >= -45
        }) else { return nil }

        if UserDefaults.standard.bool(forKey: "ride_on_landing_booked") { return nil }

        let destination = (item.location ?? "")
            .components(separatedBy: " → ").last?
            .trimmingCharacters(in: .whitespaces) ?? "your destination"

        // The location is free text ("LAS → ATL", or a city name). Only feed a
        // validated 3-letter IATA code to the estimator — otherwise it degrades to a
        // generic default ETA. If we can't find one, drop the bag-timing line so we
        // don't state a fabricated number.
        let arrivalKey = item.endDate.map { Int($0.timeIntervalSince1970) } ?? 0
        let bagLine: String = {
            guard let iata = airportIATA(from: item.location) else {
                return "You're landing soon. Line up an Uber or Lyft for when you reach the curb."
            }
            let estimate = BagDeliveryEstimator.estimate(airportIATA: iata, hasCheckedBag: true)
            return "You're landing soon. Bags usually reach the carousel about \(estimate.expectedMinutes) min after touchdown — a good time to request a ride."
        }()

        return TravelSuggestion(
            id: UUID(),
            kind: .rideOnLanding,
            title: "Line up a ride at \(destination)?",
            body: bagLine,
            action: .groundTransport,
            siriPhrase: nil,
            dismissalKey: "ride_on_landing_\(arrivalKey)"
        )
    }

    private func evaluatePackingNudge(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let trip = trips.first(where: {
            let days = wholeDays(from: now, to: $0.startDate)
            return days >= 14 && days <= 28 && $0.packingList.isEmpty && !LocalDataService.hasPackingList(tripId: $0.id)
        }) else { return nil }

        let dayCount = wholeDays(from: now, to: trip.startDate)
        return TravelSuggestion(
            id: UUID(),
            kind: .packingNudge,
            title: "Plan your \(trip.destination) packing list?",
            body: "Your trip is in \(dayCount) days. Build a list tailored to the forecast and your preferences, on this iPhone.",
            action: .packingList,
            siriPhrase: "Build my packing list in JetSetter Pro",
            dismissalKey: "packing_\(trip.id.uuidString)"
        )
    }

    private func evaluateVisaCheck(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let trip = trips.first(where: {
            let days = wholeDays(from: now, to: $0.startDate)
            return days >= 0 && days <= 7
        }) else { return nil }
        guard let visa = VisaRequirements.find(query: trip.destination),
              visa.requirementKind != .visaFree else { return nil }

        let dayCount = wholeDays(from: now, to: trip.startDate)
        return TravelSuggestion(
            id: UUID(),
            kind: .visaCheck,
            title: "Travel docs for \(visa.countryName)",
            body: "\(dayCount) day\(dayCount == 1 ? "" : "s") to go — \(visa.requirementKind.rawValue.lowercased()). Review the entry rules in Visa Requirements.",
            action: .more,
            siriPhrase: nil,
            dismissalKey: "visa_\(trip.id.uuidString)"
        )
    }

    private func evaluateWeatherWatch(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let trip = trips.first(where: {
            let days = Calendar.current.dateComponents([.day], from: now, to: $0.startDate).day ?? 0
            return days >= 0 && days <= 3
        }) else { return nil }
        return TravelSuggestion(
            id: UUID(),
            kind: .weatherWatch,
            title: "Weather check for \(trip.destination)?",
            body: "The latest forecast is on Home — worth a look before you pack.",
            action: .home,
            siriPhrase: "What's the weather at my destination in JetSetter Pro",
            dismissalKey: "weather_\(trip.id.uuidString)_\(Calendar.current.startOfDay(for: now).timeIntervalSince1970)"
        )
    }

    private func evaluateDailyBriefing(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let trip = trips.first(where: {
            $0.startDate <= now && $0.endDate >= now
        }) else { return nil }
        let dayKey = Calendar.current.startOfDay(for: now)
        return TravelSuggestion(
            id: UUID(),
            kind: .dailyBriefing,
            title: "Good \(timeOfDayGreeting(for: now)) in \(trip.destination)",
            body: "Today's weather and picks nearby are ready in Local Experiences.",
            action: .more,
            siriPhrase: nil,
            dismissalKey: "briefing_\(trip.id.uuidString)_\(dayKey.timeIntervalSince1970)"
        )
    }

    private func evaluateWelcomeHome(trips: [Trip], now: Date) -> TravelSuggestion? {
        guard let trip = trips.first(where: {
            let hours = (now.timeIntervalSince($0.endDate)) / 3600
            return hours > 0 && hours < 24
        }) else { return nil }
        return TravelSuggestion(
            id: UUID(),
            kind: .welcomeHome,
            title: "Welcome home",
            body: "Your \(trip.destination) photos can become a Trip Journal in one tap.",
            action: .more,
            siriPhrase: nil,
            dismissalKey: "welcome_\(trip.id.uuidString)"
        )
    }

    // MARK: - Dismissal

    /// Keys never expired on their own, so this set grew unbounded over a device's
    /// lifetime. Store as an insertion-ordered array and keep only the most recent
    /// `maxDismissals` — old dismissals (past trips/flights) fall off the back.
    private static let maxDismissals = 500

    func dismiss(_ suggestion: TravelSuggestion) {
        var keys = (UserDefaults.standard.array(forKey: dismissalsKey) as? [String]) ?? []
        keys.removeAll { $0 == suggestion.dismissalKey }
        keys.append(suggestion.dismissalKey)
        if keys.count > Self.maxDismissals { keys.removeFirst(keys.count - Self.maxDismissals) }
        UserDefaults.standard.set(keys, forKey: dismissalsKey)
    }

    private func dismissedKeys() -> Set<String> {
        Set((UserDefaults.standard.array(forKey: dismissalsKey) as? [String]) ?? [])
    }

    // MARK: - Helpers

    private func loadTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return [] }
        return ((try? JSONCoding.iso8601Decoder.decode([Trip].self, from: data)) ?? [])
            .sorted { $0.startDate < $1.startDate }
    }

    private func loadExpenses() -> [Expense] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_expenses") else { return [] }
        if let v = try? JSONCoding.iso8601Decoder.decode([Expense].self, from: data) { return v }
        return (try? JSONDecoder().decode([Expense].self, from: data)) ?? []   // tolerant fallback
    }

    private func loadLoyaltyAccounts() -> [LoyaltyAccount] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_loyalty_accounts")
        else { return [] }
        return (try? JSONCoding.iso8601Decoder.decode([LoyaltyAccount].self, from: data)) ?? []
    }

    /// Finds the earliest upcoming flight across all trips.
    private func nextFlight(in trips: [Trip], after now: Date) -> (Trip, ItineraryItem)? {
        let upcoming = trips.flatMap { trip in
            trip.items
                .filter { $0.type == .flight && $0.startDate > now }
                .map { (trip, $0) }
        }
        return upcoming.min { $0.1.startDate < $1.1.startDate }
    }

    /// Extracts a validated 3-letter airport code from a free-text location such as
    /// "LAS → ATL", preferring the destination (after the arrow) so a ride on landing
    /// is timed to the arrival airport. Returns nil when the text carries no IATA code
    /// (e.g. a bare city name), so callers can omit an estimate rather than fabricate one.
    private func airportIATA(from location: String?) -> String? {
        guard let loc = location, !loc.isEmpty else { return nil }
        let destination = loc.components(separatedBy: " → ").last ?? loc
        func code(in text: String) -> String? {
            guard let range = text.range(of: "\\b[A-Z]{3}\\b", options: .regularExpression)
            else { return nil }
            return String(text[range])
        }
        return code(in: destination) ?? code(in: loc)
    }

    /// Pulls "AA169" out of "Flight — AA169 JFK → NRT".
    private func extractFlightNumber(from title: String) -> String? {
        TravelStore.extractFlightNumber(from: title)
    }

    /// Whole calendar days from `now` to `date` (a trip starting tomorrow at
    /// 00:00 is "1 day away" at 22:00 tonight, not "today").
    private func wholeDays(from now: Date, to date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    private func timeOfDayGreeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default:      return "night"
        }
    }
}
