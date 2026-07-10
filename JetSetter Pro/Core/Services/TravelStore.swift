// File: Core/Services/TravelStore.swift
//
// Single source of truth for the UserDefaults-backed trip and expense
// collections shared by App Intents, IRIS tools, and feature view-models.
// Centralising the storage keys + ISO-8601 coding here keeps writers from
// drifting on encoding details (which would silently corrupt reads).

import Foundation

// `nonisolated` so IRIS tools (which run off the main actor) can read/write
// through it directly, matching the `nonisolated` Trip/Expense models.
nonisolated enum TravelStore {

    static let tripsKey    = "jetsetter_trips"
    static let expensesKey = "jetsetter_expenses"

    // MARK: - Coders

    private static func makeDecoder() -> JSONDecoder {
        JSONCoding.iso8601Decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        JSONCoding.iso8601Encoder
    }

    // MARK: - Expenses

    static func loadExpenses() -> [Expense] {
        guard let data = UserDefaults.standard.data(forKey: expensesKey) else { return [] }
        return (try? makeDecoder().decode([Expense].self, from: data)) ?? []
    }

    /// Appends an expense and notifies observers so a visible tracker refreshes.
    static func appendExpense(_ expense: Expense) {
        var existing = loadExpenses()
        existing.append(expense)
        if let data = try? makeEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: expensesKey)
            NotificationCenter.default.post(name: .jetSetterExpensesChanged, object: nil)
        }
    }

    // MARK: - Trips

    static func loadTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: tripsKey) else { return [] }
        return (try? makeDecoder().decode([Trip].self, from: data)) ?? []
    }

    static func appendTrip(_ trip: Trip) {
        var existing = loadTrips()
        existing.append(trip)
        saveTrips(existing)
    }

    /// Persists the full trip collection and notifies observers so any visible
    /// itinerary refreshes. Use this for out-of-band writes (e.g. adding a
    /// booking) so a live `ItineraryViewModel` reloads instead of later
    /// clobbering the change with its stale in-memory array.
    static func saveTrips(_ trips: [Trip]) {
        if let data = try? makeEncoder().encode(trips) {
            UserDefaults.standard.set(data, forKey: tripsKey)
            NotificationCenter.default.post(name: .jetSetterTripsChanged, object: nil)
        }
    }

    /// The active trip (today within its range) or, failing that, the next
    /// upcoming one — used as the default target for trip-scoped actions.
    static func activeOrNextTrip(now: Date = Date()) -> Trip? {
        let trips = loadTrips()
        if let active = trips.first(where: { $0.startDate <= now && $0.endDate >= now }) {
            return active
        }
        return trips.filter { $0.startDate >= now }.min(by: { $0.startDate < $1.startDate })
    }

    /// The next upcoming flight across all trips, with a normalized flight
    /// number suitable for `CheckInStateStore`.
    static func nextUpcomingFlight(now: Date = Date()) -> (flightNumber: String, departure: Date, label: String)? {
        let candidates = loadTrips().flatMap { trip in
            trip.items.filter { $0.type == .flight && $0.startDate > now }
        }
        guard let next = candidates.min(by: { $0.startDate < $1.startDate }) else { return nil }
        let number = extractFlightNumber(from: next.title) ?? next.title
        return (number, next.startDate, next.title)
    }

    // MARK: - Helpers

    /// Pulls an IATA-style flight number (e.g. "AA169") out of a free-text title.
    static func extractFlightNumber(from title: String) -> String? {
        let normalized = title.replacingOccurrences(
            of: #"([A-Z]{2,3})\s+(\d)"#,
            with: "$1$2",
            options: .regularExpression
        )
        guard let range = normalized.range(of: #"\b[A-Z]{2,3}\d{1,4}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(normalized[range])
    }
}

// MARK: - Change & action notifications

extension Notification.Name {
    /// Posted after TravelStore mutates the expense collection.
    static let jetSetterExpensesChanged = Notification.Name("jetSetterExpensesChanged")
    /// Posted after TravelStore mutates the trip collection.
    static let jetSetterTripsChanged = Notification.Name("jetSetterTripsChanged")
    /// Posted by IRIS to ask the Flight Tracker to search a specific flight.
    /// `object` is the flight-number String.
    static let jetSetterTrackFlight = Notification.Name("jetSetterTrackFlight")
    /// Posted by IRIS to ask the Packing List to (re)generate.
    static let jetSetterGeneratePackingList = Notification.Name("jetSetterGeneratePackingList")
}
