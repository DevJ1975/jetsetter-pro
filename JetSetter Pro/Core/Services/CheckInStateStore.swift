// File: Core/Services/CheckInStateStore.swift
//
// Tracks which flights the user has marked as "checked in". Used by Travel
// Intelligence to decide whether to play an urgent gate-closing alert.

import Foundation

enum CheckInStateStore {

    private static let storageKey = "jetsetter_checked_in_flights"

    /// Identifiers whose departure is older than this are pruned on every write,
    /// since a past flight never needs the checked-in flag again. Keeps the
    /// stored array (and every `isCheckedIn` read) bounded over years of use.
    private static let retentionWindow: TimeInterval = 7 * 24 * 3_600

    /// True when the user has marked this flight as checked in.
    static func isCheckedIn(flightNumber: String, departure: Date) -> Bool {
        let key = identifier(flightNumber: flightNumber, departure: departure)
        return checkedInIdentifiers().contains(key)
    }

    static func markCheckedIn(flightNumber: String, departure: Date) {
        var set = checkedInIdentifiers()
        set.insert(identifier(flightNumber: flightNumber, departure: departure))
        save(set)
    }

    static func markNotCheckedIn(flightNumber: String, departure: Date) {
        var set = checkedInIdentifiers()
        set.remove(identifier(flightNumber: flightNumber, departure: departure))
        save(set)
    }

    /// Wipes every checked-in flight. Used by the demo re-seed so each
    /// cold-launch starts with an un-checked-in baseline.
    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Helpers

    private static func identifier(flightNumber: String, departure: Date) -> String {
        // Departure timestamp suffix prevents collisions when the same flight
        // number recurs on a different date.
        "\(flightNumber.uppercased())_\(Int(departure.timeIntervalSince1970))"
    }

    private static func checkedInIdentifiers() -> Set<String> {
        guard let array = UserDefaults.standard.array(forKey: storageKey) as? [String] else {
            return []
        }
        return Set(array)
    }

    private static func save(_ set: Set<String>) {
        UserDefaults.standard.set(Array(pruned(set)), forKey: storageKey)
    }

    /// Drops identifiers whose encoded departure timestamp is more than
    /// `retentionWindow` in the past. Identifiers we can't parse are kept
    /// (fail-safe: never lose a flag we can't reason about).
    private static func pruned(_ set: Set<String>) -> Set<String> {
        let cutoff = Date().addingTimeInterval(-retentionWindow).timeIntervalSince1970
        return set.filter { identifier in
            guard let underscore = identifier.lastIndex(of: "_") else { return true }
            let suffix = identifier[identifier.index(after: underscore)...]
            guard let timestamp = TimeInterval(suffix) else { return true }
            return timestamp >= cutoff
        }
    }
}
