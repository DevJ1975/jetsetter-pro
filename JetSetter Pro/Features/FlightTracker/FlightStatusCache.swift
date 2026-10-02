// File: Features/FlightTracker/FlightStatusCache.swift
//
// The last flight status FlightAware returned, kept on the device per flight
// number. A traveler opens the tracker at the gate in airplane mode, or behind
// a hotel captive portal, and still sees the gate and times from the last good
// fetch, stamped "Updated 40 min ago", instead of a blank screen.
//
// Stored through `CodableDefaults` like the packing-list and wallet caches.
// Everything lives under one key and is pruned on every save (at most
// `maxEntries` flights, none older than `maxAge`), so searching a hundred
// flight numbers can't grow UserDefaults without bound. Flight status is
// public timetable data, so it doesn't belong in the vault.

import Foundation

/// One saved search: the flights returned for a flight number, and when.
struct CachedFlightStatus: Codable {
    let ident: String
    let flights: [Flight]
    let fetchedAt: Date
}

struct FlightStatusCache {

    static let storageKey = "flight_status_cache_v1"
    /// Enough for a multi-leg trip plus a few lookups for colleagues.
    static let maxEntries = 20
    /// A status older than this describes a flight that has long since landed.
    static let maxAge: TimeInterval = 3 * 86_400

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests use a throwaway suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// "ua 2391" and "UA2391" are the same flight.
    static func normalized(_ ident: String) -> String {
        ident.uppercased().filter { !$0.isWhitespace }
    }

    func load(ident: String) -> CachedFlightStatus? {
        allEntries()[Self.normalized(ident)]
    }

    /// The most recently fetched flight, for reopening the tracker where the
    /// traveler left it.
    func mostRecent() -> CachedFlightStatus? {
        allEntries().values.max { $0.fetchedAt < $1.fetchedAt }
    }

    /// Saves a successful fetch. An empty result is not saved: "no flights
    /// found" mustn't overwrite the last good status for that number.
    func save(_ flights: [Flight], ident: String, fetchedAt: Date) {
        guard !flights.isEmpty else { return }
        let key = Self.normalized(ident)
        var entries = allEntries()
        entries[key] = CachedFlightStatus(ident: key, flights: flights, fetchedAt: fetchedAt)
        write(Self.pruned(entries, now: fetchedAt))
    }

    /// Replaces one flight inside a saved search, used when the detail screen
    /// refreshes a single flight. Does nothing when that search, or that flight
    /// in it, isn't saved. The entry keeps its original time: only one of its
    /// flights is newer, and "Updated X ago" must never overstate freshness.
    func update(_ flight: Flight, ident: String) {
        let key = Self.normalized(ident)
        var entries = allEntries()
        guard let entry = entries[key],
              let index = entry.flights.firstIndex(where: { $0.faFlightId == flight.faFlightId })
        else { return }
        var flights = entry.flights
        flights[index] = flight
        entries[key] = CachedFlightStatus(ident: key, flights: flights, fetchedAt: entry.fetchedAt)
        write(entries)
    }

    func removeAll() {
        CodableDefaults.remove(forKey: Self.storageKey, from: defaults)
    }

    // MARK: - Storage

    private func allEntries() -> [String: CachedFlightStatus] {
        CodableDefaults.load([String: CachedFlightStatus].self, forKey: Self.storageKey, from: defaults) ?? [:]
    }

    private func write(_ entries: [String: CachedFlightStatus]) {
        try? CodableDefaults.save(entries, forKey: Self.storageKey, to: defaults)
    }

    /// Drops entries older than `maxAge`, then keeps the newest `maxEntries`.
    static func pruned(_ entries: [String: CachedFlightStatus], now: Date) -> [String: CachedFlightStatus] {
        let fresh = entries.filter { now.timeIntervalSince($0.value.fetchedAt) <= maxAge }
        let newest = fresh.values
            .sorted { $0.fetchedAt > $1.fetchedAt }
            .prefix(maxEntries)
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`, which traps on
        // a duplicate; keep the newer entry (the list is newest first).
        return Dictionary(newest.map { ($0.ident, $0) }, uniquingKeysWith: { newer, _ in newer })
    }
}
