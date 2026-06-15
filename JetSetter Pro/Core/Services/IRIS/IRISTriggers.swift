// File: Core/Services/IRIS/IRISTriggers.swift
//
// Decides when IRIS speaks first. Evaluates trip state + time-of-day and
// returns the highest-priority suggestion. Each suggestion has a dismissal
// key so the same nudge doesn't reappear after the user swipes it away.

import Foundation
import Combine

// MARK: - Suggestion

struct IRISSuggestion: Identifiable, Equatable {
    let id: UUID
    let kind: Kind
    let title: String
    let body: String
    let promptToIRIS: String        // What IRIS will say if user taps "Talk to IRIS"
    let dismissalKey: String        // Bucket for de-dup

    enum Kind: String, CaseIterable {
        case checkInWindow      // < 24h to next flight, not yet checked in
        case tierAtRisk         // Loyalty tier expires within 7 days
        case rideToAirport      // < 12h to next flight, no Uber pre-booked
        case packingNudge       // 14-28 days out, no packing list
        case visaCheck          // 7 days out, eVisa or visaRequired
        case weatherWatch       // 3 days out, rain in forecast
        case dailyBriefing      // First open of the day during active trip
        case welcomeHome        // < 24h after trip ended

        var systemImage: String {
            switch self {
            case .checkInWindow:   return "checkmark.seal.fill"
            case .tierAtRisk:      return "crown.fill"
            case .rideToAirport:   return "car.fill"
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
final class IRISTriggers: ObservableObject {

    static let shared = IRISTriggers()
    private init() {}

    private let dismissalsKey = "iris_dismissed_suggestions"

    /// Returns the highest-priority suggestion the user hasn't dismissed.
    /// Call from HomeViewModel on every load.
    func evaluate(now: Date = Date()) -> IRISSuggestion? {
        evaluateAll(now: now).first
    }

    /// Returns ALL active suggestions in priority order, filtered by the
    /// dismissal set. HomeViewModel uses this to drive a "+N more" badge.
    func evaluateAll(now: Date = Date()) -> [IRISSuggestion] {
        let trips = loadTrips()
        let dismissals = dismissedKeys()

        // Priority order: checkInWindow > tierAtRisk > rideToAirport >
        // packingNudge > visaCheck > weatherWatch > dailyBriefing > welcomeHome.
        let candidates: [IRISSuggestion?] = [
            evaluateCheckInWindow(trips: trips, now: now),
            evaluateTierAtRisk(now: now),
            evaluateRideToAirport(trips: trips, now: now),
            evaluatePackingNudge(trips: trips, now: now),
            evaluateVisaCheck(trips: trips, now: now),
            evaluateWeatherWatch(trips: trips, now: now),
            evaluateDailyBriefing(trips: trips, now: now),
            evaluateWelcomeHome(trips: trips, now: now)
        ]

        return candidates
            .compactMap { $0 }
            .filter { !dismissals.contains($0.dismissalKey) }
    }

    // MARK: - Triggers

    /// Fires when the next flight departs in < 24h and the user hasn't
    /// marked it as checked-in yet. One-shot via dismissalKey.
    private func evaluateCheckInWindow(trips: [Trip], now: Date) -> IRISSuggestion? {
        guard let (_, item) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 0, hours < 24 else { return nil }

        let flightNumber = extractFlightNumber(from: item.title) ?? "your flight"
        guard !CheckInStateStore.isCheckedIn(
            flightNumber: flightNumber,
            departure: item.startDate
        ) else { return nil }

        let hoursText = max(1, Int(hours.rounded()))
        return IRISSuggestion(
            id: UUID(),
            kind: .checkInWindow,
            title: "Check in to \(flightNumber)?",
            body: "Your flight leaves in \(hoursText) hour\(hoursText == 1 ? "" : "s"). Want me to walk you through check-in?",
            promptToIRIS: "Walk me through online check-in for \(flightNumber).",
            dismissalKey: "checkin_\(flightNumber)_\(Int(item.startDate.timeIntervalSince1970))"
        )
    }

    /// Fires when any saved loyalty account's tier expiration is within 7 days.
    private func evaluateTierAtRisk(now: Date) -> IRISSuggestion? {
        let accounts = loadLoyaltyAccounts()
        let cal = Calendar.current
        let weekday = DateFormatter(); weekday.dateFormat = "EEEE"

        guard let atRisk = accounts.first(where: { acct in
            guard let expiry = acct.tierExpiration else { return false }
            let days = cal.dateComponents([.day], from: now, to: expiry).day ?? Int.max
            return days >= 0 && days <= 7
        }) else { return nil }

        let programName = LoyaltyProgramCatalog.find(id: atRisk.programID)?.name ?? atRisk.programID
        let expiryLabel: String = {
            guard let date = atRisk.tierExpiration else { return "soon" }
            return weekday.string(from: date)
        }()
        let expiryKey = atRisk.tierExpiration.map { Int($0.timeIntervalSince1970) } ?? 0

        return IRISSuggestion(
            id: UUID(),
            kind: .tierAtRisk,
            title: "\(programName) \(atRisk.tier) at risk",
            body: "\(programName) \(atRisk.tier) expires \(expiryLabel) — book Park Hyatt to renew.",
            promptToIRIS: "Help me protect my \(programName) \(atRisk.tier) status — what's the fastest way to renew?",
            dismissalKey: "tier_at_risk_\(atRisk.programID)_\(expiryKey)"
        )
    }

    /// Fires when the next flight departs in < 12h and the user hasn't
    /// flagged an Uber as already booked (uber_booked UserDefaults flag).
    private func evaluateRideToAirport(trips: [Trip], now: Date) -> IRISSuggestion? {
        guard let (_, item) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 0, hours < 12 else { return nil }

        if UserDefaults.standard.bool(forKey: "uber_booked") { return nil }

        let origin = (item.location ?? "")
            .components(separatedBy: " → ")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? "the airport"

        return IRISSuggestion(
            id: UUID(),
            kind: .rideToAirport,
            title: "Pre-book your ride to \(origin)?",
            body: "Your flight leaves in under \(Int(hours.rounded() + 1)) hours. I can lock in an Uber Black now.",
            promptToIRIS: "Pre-book an Uber to \(origin) for my upcoming flight.",
            dismissalKey: "ride_to_airport_\(Int(item.startDate.timeIntervalSince1970))"
        )
    }

    private func evaluatePackingNudge(trips: [Trip], now: Date) -> IRISSuggestion? {
        guard let trip = trips.first(where: {
            let days = Calendar.current.dateComponents([.day], from: now, to: $0.startDate).day ?? 0
            return days >= 14 && days <= 28 && $0.packingList.isEmpty
        }) else { return nil }

        let dayCount = Calendar.current.dateComponents([.day], from: now, to: trip.startDate).day ?? 0
        return IRISSuggestion(
            id: UUID(),
            kind: .packingNudge,
            title: "Plan your \(trip.destination) packing list?",
            body: "Your trip is in \(dayCount) days. I can build a smart list tailored to the weather and your preferences.",
            promptToIRIS: "Build me a packing list for my upcoming \(trip.destination) trip.",
            dismissalKey: "packing_\(trip.id.uuidString)"
        )
    }

    private func evaluateVisaCheck(trips: [Trip], now: Date) -> IRISSuggestion? {
        guard let trip = trips.first(where: {
            let days = Calendar.current.dateComponents([.day], from: now, to: $0.startDate).day ?? 0
            return days >= 0 && days <= 7
        }) else { return nil }
        guard let visa = VisaRequirements.find(query: trip.destination),
              visa.requirementKind != .visaFree else { return nil }

        let dayCount = Calendar.current.dateComponents([.day], from: now, to: trip.startDate).day ?? 0
        return IRISSuggestion(
            id: UUID(),
            kind: .visaCheck,
            title: "Travel docs for \(visa.countryName)",
            body: "\(dayCount) day\(dayCount == 1 ? "" : "s") to go — \(visa.requirementKind.rawValue.lowercased()). I can walk you through it.",
            promptToIRIS: "What do I need to know about visa and entry requirements for \(visa.countryName)?",
            dismissalKey: "visa_\(trip.id.uuidString)"
        )
    }

    private func evaluateWeatherWatch(trips: [Trip], now: Date) -> IRISSuggestion? {
        guard let trip = trips.first(where: {
            let days = Calendar.current.dateComponents([.day], from: now, to: $0.startDate).day ?? 0
            return days >= 0 && days <= 3
        }) else { return nil }
        return IRISSuggestion(
            id: UUID(),
            kind: .weatherWatch,
            title: "Weather check for \(trip.destination)?",
            body: "I can pull the latest forecast and flag anything to pack for.",
            promptToIRIS: "Check the weather for my upcoming \(trip.destination) trip and tell me what to expect.",
            dismissalKey: "weather_\(trip.id.uuidString)_\(Calendar.current.startOfDay(for: now).timeIntervalSince1970)"
        )
    }

    private func evaluateDailyBriefing(trips: [Trip], now: Date) -> IRISSuggestion? {
        guard let trip = trips.first(where: {
            $0.startDate <= now && $0.endDate >= now
        }) else { return nil }
        let dayKey = Calendar.current.startOfDay(for: now)
        return IRISSuggestion(
            id: UUID(),
            kind: .dailyBriefing,
            title: "Good \(timeOfDayGreeting(for: now)) in \(trip.destination)",
            body: "Want today's brief — weather, what's open, things you might enjoy?",
            promptToIRIS: "Give me today's travel briefing for \(trip.destination) — weather, local time, and 3 things I might enjoy.",
            dismissalKey: "briefing_\(trip.id.uuidString)_\(dayKey.timeIntervalSince1970)"
        )
    }

    private func evaluateWelcomeHome(trips: [Trip], now: Date) -> IRISSuggestion? {
        guard let trip = trips.first(where: {
            let hours = (now.timeIntervalSince($0.endDate)) / 3600
            return hours > 0 && hours < 24
        }) else { return nil }
        return IRISSuggestion(
            id: UUID(),
            kind: .welcomeHome,
            title: "Welcome home",
            body: "Want me to put together a Trip Journal from your \(trip.destination) photos?",
            promptToIRIS: "Help me reflect on my \(trip.destination) trip — what should I do with my photos and notes?",
            dismissalKey: "welcome_\(trip.id.uuidString)"
        )
    }

    // MARK: - Dismissal

    func dismiss(_ suggestion: IRISSuggestion) {
        var set = dismissedKeys()
        set.insert(suggestion.dismissalKey)
        UserDefaults.standard.set(Array(set), forKey: dismissalsKey)
    }

    private func dismissedKeys() -> Set<String> {
        Set((UserDefaults.standard.array(forKey: dismissalsKey) as? [String]) ?? [])
    }

    // MARK: - Helpers

    private func loadTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return ((try? d.decode([Trip].self, from: data)) ?? [])
            .sorted { $0.startDate < $1.startDate }
    }

    private func loadLoyaltyAccounts() -> [LoyaltyAccount] {
        guard let data = UserDefaults.standard.data(forKey: DemoSeeder.loyaltyAccountsKey)
        else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([LoyaltyAccount].self, from: data)) ?? []
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

    /// Pulls "AA169" out of "Flight — AA169 JFK → NRT".
    private func extractFlightNumber(from title: String) -> String? {
        guard let range = title.range(of: "[A-Z]{2,3}\\d{1,4}", options: .regularExpression)
        else { return nil }
        return String(title[range])
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
