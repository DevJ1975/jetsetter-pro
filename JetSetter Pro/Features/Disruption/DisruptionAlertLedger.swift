// File: Features/Disruption/DisruptionAlertLedger.swift
//
// What the disruption monitor has already told the traveler, and the last
// departure gate it saw, per flight instance. Persisted so it survives the
// background relaunches BGAppRefreshTask causes.
//
// Two past defects this exists to stop:
//  • A 45-minute-plus delay created a new disruption event and played the cabin
//    chime on EVERY poll (every ~10 minutes) for as long as the flight stayed
//    delayed. Now an alert is sent once, and again only when it materially
//    changes (a bigger delay bucket, a different gate, a different diversion
//    airport).
//  • The previous gate lived only in memory, so after a background relaunch
//    the monitor had nothing to compare against and missed the gate change.
//
// Keys are per flight *instance*, not per flight number: DL1423 flies every
// day, and yesterday's delay must never suppress (or trigger) today's alert.
// Entries are pruned after a few days so the blob stays small.

import Foundation

// MARK: - Alert

/// One alert the monitor wants to send: the kind plus the value that makes it
/// news. The value is what dedupe compares: the delay bucket in minutes, the
/// new gate, the diversion airport, or a constant for one-shot alerts.
nonisolated struct DisruptionAlert: Equatable {
    let type: DisruptionType
    let value: String
}

// MARK: - Ledger

/// A remembered value and when it was last written, used for both sent alerts
/// and known gates so pruning works the same way for each.
nonisolated struct DisruptionLedgerEntry: Codable, Equatable {
    var value: String
    var recordedAt: Date
}

/// Pure, persisted record of sent alerts and last-seen gates. Value type so the
/// dedupe rules can be tested without UserDefaults or the network.
nonisolated struct DisruptionAlertLedger: Codable, Equatable {

    /// "<flightKey>|<type>" → the value last alerted for that flight and type.
    var alerts: [String: DisruptionLedgerEntry] = [:]
    /// "<flightKey>" → the last departure gate FlightAware reported.
    var gates: [String: DisruptionLedgerEntry] = [:]

    /// How long an entry is kept. Longer than any flight plus its ±6 h polling
    /// window, short enough that the blob never grows without bound.
    static let retention: TimeInterval = 4 * 86_400

    // MARK: Keys

    /// Identifies one flight instance. FlightAware's `fa_flight_id` is unique per
    /// instance, so it's preferred. Without it, fall back to the flight number
    /// plus the departure date *at the origin airport*: a 23:30 Las Vegas
    /// departure is already tomorrow in UTC and in an Atlanta-based traveler's
    /// device zone, and keying on either would split or merge instances. With
    /// no known origin zone we use UTC, which at least doesn't change when the
    /// traveler's phone changes zones mid-trip.
    static func flightKey(
        faFlightId: String?,
        flightNumber: String,
        scheduledDeparture: Date,
        originTimeZone: TimeZone?
    ) -> String {
        if let id = faFlightId?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
            return id
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = originTimeZone ?? TimeZone(identifier: "UTC") ?? .current
        let day = calendar.dateComponents([.year, .month, .day], from: scheduledDeparture)
        let date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return "\(flightNumber.uppercased())#\(date)"
    }

    private static func alertKey(flightKey: String, type: DisruptionType) -> String {
        "\(flightKey)|\(type.rawValue)"
    }

    // MARK: Alerts

    /// True when `alert` is news for this flight: nothing of its type was sent
    /// yet, or the value changed materially. A delay only counts when it grows
    /// into a bigger bucket. A delay that shrinks again isn't worth a chime.
    func shouldSend(_ alert: DisruptionAlert, flightKey: String) -> Bool {
        guard let previous = alerts[Self.alertKey(flightKey: flightKey, type: alert.type)]?.value else {
            return true
        }
        switch alert.type {
        case .majorDelay:
            return (Int(alert.value) ?? 0) > (Int(previous) ?? 0)
        case .cancellation, .gateChange, .missedConnection, .diversion:
            return alert.value != previous
        }
    }

    mutating func recordSent(_ alert: DisruptionAlert, flightKey: String, at now: Date) {
        alerts[Self.alertKey(flightKey: flightKey, type: alert.type)] =
            DisruptionLedgerEntry(value: alert.value, recordedAt: now)
    }

    // MARK: Gates

    func knownGate(flightKey: String) -> String? {
        gates[flightKey]?.value
    }

    mutating func recordGate(_ gate: String, flightKey: String, at now: Date) {
        gates[flightKey] = DisruptionLedgerEntry(value: gate, recordedAt: now)
    }

    // MARK: Pruning

    /// Drops entries older than `retention`. Gates are rewritten on every poll,
    /// so an active flight's gate never ages out mid-trip.
    mutating func prune(now: Date) {
        alerts = alerts.filter { now.timeIntervalSince($0.value.recordedAt) < Self.retention }
        gates = gates.filter { now.timeIntervalSince($0.value.recordedAt) < Self.retention }
    }
}

// MARK: - Store

/// Persists the ledger with `CodableDefaults`, the same Codable-over-UserDefaults
/// path the other small on-device stores use. Main-actor so each
/// read-modify-write in `mutate` is atomic with respect to the monitor's
/// concurrent per-flight checks: two overlapping polls can't both claim the
/// same alert.
@MainActor
final class DisruptionAlertLedgerStore {

    static let shared = DisruptionAlertLedgerStore()

    static let storageKey = "jetsetter_disruption_alert_ledger"

    private let defaults: UserDefaults

    /// Internal rather than private so tests can point it at a throwaway suite
    /// and prove the ledger survives a fresh instance (a relaunch).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The persisted ledger, or an empty one when none is stored or it no
    /// longer decodes. Losing it only risks one repeated alert.
    var ledger: DisruptionAlertLedger {
        CodableDefaults.load(DisruptionAlertLedger.self, forKey: Self.storageKey, from: defaults)
            ?? DisruptionAlertLedger()
    }

    /// Loads, applies `body`, prunes and saves in one synchronous step.
    @discardableResult
    func mutate<T>(now: Date = Date(), _ body: (inout DisruptionAlertLedger) -> T) -> T {
        var ledger = self.ledger
        let result = body(&ledger)
        ledger.prune(now: now)
        try? CodableDefaults.save(ledger, forKey: Self.storageKey, to: defaults)
        return result
    }
}
