// File: Core/Services/Persistence/WidgetBridge.swift
//
// App-side feed for the Home Screen "Next Trip" widget. The widget runs in a
// separate process and must not compile the whole app, so instead of reading
// `TravelStore` directly it reads a tiny `NextTripSnapshot` the app publishes to
// a shared App Group `UserDefaults` on every trip change. The app also asks
// WidgetKit to reload the widget's timeline so it updates within seconds.
//
// App Group: until the `group.DevJ.JetSetter-Pro` App Group capability is added
// to both the app and the widget targets, `UserDefaults(suiteName:)` returns nil
// and we fall back to `.standard` — so this is safe to ship now and starts
// sharing cross-process automatically once the capability exists.

import Foundation
import WidgetKit

// MARK: - Shared snapshot

/// Minimal, dependency-free projection of the active/next trip for the widget.
/// Duplicated (not shared) in the widget target so the extension stays tiny.
struct NextTripSnapshot: Codable {
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
}

// MARK: - WidgetBridge

enum WidgetBridge {

    static let appGroupID = "group.DevJ.JetSetter-Pro"
    static let nextTripKey = "jetsetter_next_trip_snapshot"
    static let nextTripWidgetKind = "NextTripWidget"

    /// Shared defaults if the App Group is available, else the standard domain
    /// (pre-capability fallback — in-process only).
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Publishes the active-or-next trip to shared storage and reloads the widget.
    /// Computed from the passed array (NOT via `TravelStore.activeOrNextTrip()`,
    /// which would re-enter the persistence lock when called mid-write).
    static func publishNextTrip(from trips: [Trip], now: Date = Date()) {
        let snapshot = activeOrNext(in: trips, now: now).map {
            NextTripSnapshot(name: $0.name, destination: $0.destination,
                             startDate: $0.startDate, endDate: $0.endDate)
        }

        if let snapshot, let data = try? JSONCoding.iso8601Encoder.encode(snapshot) {
            sharedDefaults.set(data, forKey: nextTripKey)
        } else {
            sharedDefaults.removeObject(forKey: nextTripKey)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: nextTripWidgetKind)
    }

    /// The active trip (today within its range) or the soonest upcoming one.
    /// Mirrors `TravelStore.activeOrNextTrip` but operates on an in-memory array.
    private static func activeOrNext(in trips: [Trip], now: Date) -> Trip? {
        if let active = trips.first(where: { $0.startDate <= now && $0.endDate >= now }) {
            return active
        }
        return trips.filter { $0.startDate >= now }.min(by: { $0.startDate < $1.startDate })
    }
}
