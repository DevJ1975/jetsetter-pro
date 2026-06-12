// File: Core/Services/CheckInStateStore.swift
//
// Tracks which flights the user has marked as "checked in". Used by Travel
// Intelligence to decide whether to play an urgent gate-closing alert.

import Foundation

enum CheckInStateStore {

    private static let storageKey = "jetsetter_checked_in_flights"

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
        UserDefaults.standard.set(Array(set), forKey: storageKey)
    }
}
