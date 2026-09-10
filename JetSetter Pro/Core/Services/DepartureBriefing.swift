// File: Core/Services/DepartureBriefing.swift
//
// Single shared source for the "when should I leave?" briefing so Siri, Home
// and the Departure Optimizer screen never contradict each other. It holds the
// last LIVE recommendation the optimizer computed; when none exists yet there
// is simply no briefing (callers say so instead of quoting placeholder numbers).

import Foundation

struct DepartureBriefing {
    let leaveBy: String        // "5:19 AM"
    let driveMinutes: Int      // 34
    let tsaMinutes: Int        // 22
    let weatherLabel: String   // "Clear skies"
    let temperatureF: Int?     // 74, nil when weather was unavailable
    let flightNumber: String   // "DL1423"
    let originIATA: String     // "LAS"
    let computedAt: Date

    /// Last live recommendation, published by `DepartureOptimizerService`.
    /// Written on the main actor by the optimizer and read from intents that
    /// aren't actor-isolated, so all access is serialized through `cachedLiveLock`.
    private nonisolated(unsafe) static var _cachedLive: DepartureBriefing?
    private static let cachedLiveLock = NSLock()

    static var cachedLive: DepartureBriefing? {
        get {
            cachedLiveLock.lock()
            defer { cachedLiveLock.unlock() }
            return _cachedLive
        }
        set {
            cachedLiveLock.lock()
            defer { cachedLiveLock.unlock() }
            _cachedLive = newValue
        }
    }

    /// The briefing to quote, if the optimizer has produced one this session.
    static func current() -> DepartureBriefing? { cachedLive }

    /// One-line spoken/plain summary.
    var summary: String {
        var line = "Leave by \(leaveBy) for \(flightNumber) from \(originIATA): about a \(driveMinutes)-minute drive and roughly \(tsaMinutes) minutes at security"
        if let temperatureF {
            line += ", \(weatherLabel.lowercased()) and \(temperatureF)°F."
        } else {
            line += "."
        }
        return line
    }
}
