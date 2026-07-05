// File: Core/Services/IRIS/DepartureBriefing.swift
//
// Single shared source for the "when should I leave?" briefing so IRIS can never
// contradict the Departure Optimizer screen (IOS_PARITY_NOTES.md §4, §7.3). The
// demo tier reads the seeded persona defaults (leave by 5:19 AM, 34-min drive,
// TSA 22m, clear 74°F for the 7:00 AM DL 1423); once the Departure Optimizer has
// computed a live recommendation this returns those values instead.

import Foundation

struct DepartureBriefing {
    let leaveBy: String        // "5:19 AM"
    let driveMinutes: Int      // 34
    let tsaMinutes: Int        // 22
    let weatherLabel: String   // "Clear skies"
    let temperatureF: Int      // 74
    let flightNumber: String   // "DL 1423"
    let originIATA: String     // "LAS"

    /// Persona defaults (§7.1) — identical to what the Departure Optimizer shows
    /// for the seeded 7:00 AM flight before any live re-roll.
    static let personaDefault = DepartureBriefing(
        leaveBy: "5:19 AM",
        driveMinutes: 34,
        tsaMinutes: 22,
        weatherLabel: "Clear skies",
        temperatureF: 74,
        flightNumber: "DL 1423",
        originIATA: "LAS"
    )

    /// Last live recommendation, published by `DepartureOptimizerService` so a
    /// re-rolled drive/TSA/weather flows through to IRIS. `nil` until computed.
    /// Written on the main actor by the optimizer and read from IRIS tools that
    /// aren't actor-isolated, so all access is serialized through `cachedLiveLock`.
    private nonisolated(unsafe) static var _cachedLive: DepartureBriefing?
    private static let cachedLiveLock = NSLock()

    /// Thread-safe accessor for the last live recommendation.
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

    /// The briefing IRIS should quote — live if available, else persona default.
    static func current() -> DepartureBriefing {
        cachedLive ?? personaDefault
    }

    /// One-line summary used in IRIS replies.
    var summary: String {
        "leave by **\(leaveBy)** — \(driveMinutes)-min drive, TSA about \(tsaMinutes) min, "
        + "\(weatherLabel.lowercased()) and \(temperatureF)°F at \(originIATA)"
    }
}
