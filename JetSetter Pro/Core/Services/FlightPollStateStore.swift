// File: Core/Services/FlightPollStateStore.swift
//
// Durable cross-poll comparison state for flight monitoring.
//
// WHY THIS EXISTS: DisruptionMonitorService used to hold the last-observed gate
// per flight in a plain in-memory `[String: String]`. BGAppRefreshTask commonly
// runs in a FRESH PROCESS after the app was terminated, so that dictionary was
// empty on every background wake: the monitor read `previousGate = nil`, could
// not detect a change, and merely re-seeded the cache — meaning a gate change
// was, in the common background case, NEVER detected. This persists the cache to
// UserDefaults so a comparison survives process restarts, which is what makes
// background gate-change detection actually work.
//
// Modeled on `CheckInStateStore`: a static enum, one UserDefaults key, and a
// retention window pruned on every write so the store can't grow unbounded.
//
// The cache key is an opaque `String` supplied by the caller. Today the monitor
// scopes it by trip + flight number; when tracked flights land it becomes
// `faFlightId`. Because the key is opaque here, that change needs no edit to
// this store.
//
// `nonisolated` throughout so the `DisruptionMonitorService` actor (which is NOT
// MainActor) can read/write synchronously. UserDefaults access is thread-safe,
// and the encoder/decoder use ONE explicit `.iso8601` date strategy on both
// sides — never mix a key/date strategy with explicit coding keys (the audit
// documents two data-loss bugs caused by exactly that mismatch).

import Foundation

enum FlightPollStateStore {

    private nonisolated static let storageKey = "jetsetter_flight_poll_gate_cache_v1"

    /// Entries observed longer ago than this are pruned on write. A week comfortably
    /// covers any flight's active monitoring window while bounding the store.
    private nonisolated static let retentionWindow: TimeInterval = 7 * 24 * 3_600

    /// One observed gate for one flight instance, timestamped for pruning.
    private struct GateObservation: Codable {
        let gate: String
        let observedAt: Date
    }

    // MARK: - Public API

    /// The last gate observed for `key`, or nil if none is cached (first poll, or
    /// pruned/absent). A nil here legitimately means "no prior observation".
    nonisolated static func lastKnownGate(for key: String) -> String? {
        load()[key]?.gate
    }

    /// Records the currently-observed gate for `key`, replacing any prior value,
    /// and prunes stale entries in the same write.
    nonisolated static func setGate(_ gate: String, for key: String) {
        var map = load()
        map[key] = GateObservation(gate: gate, observedAt: Date())
        save(pruned(map))
    }

    /// Removes the cached observation for a single flight instance — call when a
    /// flight is untracked or completes so its key doesn't linger until pruning.
    nonisolated static func clear(for key: String) {
        var map = load()
        guard map.removeValue(forKey: key) != nil else { return }
        save(map)
    }

    /// Wipes the entire cache.
    nonisolated static func resetAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Storage

    private nonisolated static func load() -> [String: GateObservation] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Fail-safe: a decode failure returns empty rather than trapping. This is
        // reconstructible comparison state (the next poll re-seeds it), not user
        // data, so self-healing on corruption is the correct trade-off.
        return (try? decoder.decode([String: GateObservation].self, from: data)) ?? [:]
    }

    private nonisolated static func save(_ map: [String: GateObservation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Drops observations older than `retentionWindow`.
    private nonisolated static func pruned(_ map: [String: GateObservation]) -> [String: GateObservation] {
        let cutoff = Date().addingTimeInterval(-retentionWindow)
        return map.filter { $0.value.observedAt >= cutoff }
    }
}
