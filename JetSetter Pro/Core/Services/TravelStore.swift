// File: Core/Services/TravelStore.swift
//
// Single source of truth for the trip and expense collections shared by App
// Intents, IRIS tools, and feature view-models. Trips are persisted via SwiftData
// (see JetDataStore); expenses remain on UserDefaults for now. The public API is
// unchanged so callers don't need edits.

import Foundation

// `nonisolated` so IRIS tools (which run off the main actor) can read/write
// through it directly, matching the `nonisolated` Trip/Expense models.
nonisolated enum TravelStore {

    static let tripsKey    = "jetsetter_trips"
    static let expensesKey = "jetsetter_expenses"

    // MARK: - Serialization (expenses only)

    // Expenses still use a UserDefaults read-modify-write, so keep a lock for
    // them. Trips are serialized inside `JetDataStore` instead.
    private static let expenseLock = NSLock()

    // MARK: - Coders

    private static func makeDecoder() -> JSONDecoder {
        JSONCoding.iso8601Decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        JSONCoding.iso8601Encoder
    }

    // MARK: - Expenses

    static func loadExpenses() -> [Expense] {
        expenseLock.lock(); defer { expenseLock.unlock() }
        return loadExpensesUnlocked()
    }

    private static func loadExpensesUnlocked() -> [Expense] {
        guard let data = UserDefaults.standard.data(forKey: expensesKey) else { return [] }
        return (try? makeDecoder().decode([Expense].self, from: data)) ?? []
    }

    /// Appends an expense and notifies observers so a visible tracker refreshes.
    static func appendExpense(_ expense: Expense) {
        expenseLock.lock()
        var existing = loadExpensesUnlocked()
        existing.append(expense)
        let data = try? makeEncoder().encode(existing)
        if let data { UserDefaults.standard.set(data, forKey: expensesKey) }
        expenseLock.unlock()
        // Post outside the lock so observers can't re-enter a mutator mid-hold.
        if data != nil {
            NotificationCenter.default.post(name: .jetSetterExpensesChanged, object: nil)
        }
    }

    // MARK: - Trips (SwiftData-backed via JetDataStore)

    /// Loads the saved trips from SwiftData. Legacy UserDefaults blobs (including
    /// older `.deferredToDate` encodings) are imported once by `JetDataStore` on
    /// first launch, so no reader ever gets a silently-wiped list.
    static func loadTrips() -> [Trip] {
        JetDataStore.withContext { JetDataStore.fetchTrips($0) }
    }

    static func appendTrip(_ trip: Trip) {
        mutateTrips { $0.append(trip) }
    }

    /// Inserts `trip` if no trip with its `id` exists, or replaces the existing
    /// one in place (preserving position) if it does. The whole read-modify-write
    /// is atomic, so an out-of-band mutation (e.g. a booking flow) never clobbers
    /// concurrent edits. Returns the persisted collection so callers can avoid a
    /// second read.
    @discardableResult
    static func upsertTrip(_ trip: Trip) -> [Trip] {
        mutateTrips { existing in
            if let index = existing.firstIndex(where: { $0.id == trip.id }) {
                existing[index] = trip
            } else {
                existing.append(trip)
            }
        }
    }

    /// Appends an itinerary item to the trip identified by `tripID`, atomically.
    /// No-op (and returns `false`) when no trip matches, so callers can fall back
    /// to creating a dedicated trip.
    @discardableResult
    static func appendItem(_ item: ItineraryItem, toTripID tripID: UUID) -> Bool {
        var didAppend = false
        mutateTrips { existing in
            guard let index = existing.firstIndex(where: { $0.id == tripID }) else { return }
            existing[index].items.append(item)
            didAppend = true
        }
        return didAppend
    }

    /// Atomically loads the freshest trip collection, applies `body`, persists
    /// the result, and notifies observers. This is the single funnel for trip
    /// mutations: `JetDataStore.withContext` serializes the load→modify→save under
    /// one lock, so no concurrent writer can lose an update. Returns the persisted
    /// collection so a caller (e.g. a view model) can reflect the authoritative
    /// post-write state without a second read.
    @discardableResult
    static func mutateTrips(_ body: (inout [Trip]) -> Void) -> [Trip] {
        let trips = JetDataStore.withContext { context -> [Trip] in
            var trips = JetDataStore.fetchTrips(context)
            body(&trips)
            JetDataStore.writeTrips(trips, context)
            return trips
        }
        // Post outside the store lock so an observer can't re-enter a mutator
        // while the lock is held.
        NotificationCenter.default.post(name: .jetSetterTripsChanged, object: nil)
        return trips
    }

    /// Persists the full trip collection and notifies observers. Prefer
    /// `mutateTrips`/`upsertTrip`/`appendItem` for edits; this full-replace is for
    /// callers that already hold the complete authoritative array.
    static func saveTrips(_ trips: [Trip]) {
        JetDataStore.withContext { JetDataStore.writeTrips(trips, $0) }
        NotificationCenter.default.post(name: .jetSetterTripsChanged, object: nil)
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
