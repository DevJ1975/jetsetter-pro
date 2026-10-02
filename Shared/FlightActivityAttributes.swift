// File: Shared/FlightActivityAttributes.swift
//
// Shared Live Activity payload types. This file is the ONLY one that must be a
// member of BOTH the app target and the Widget Extension target — it has no
// dependencies beyond Foundation + ActivityKit, so it compiles cleanly in the
// extension. See SETUP-LIVE-ACTIVITY.md.
//
// Wire compatibility: the Django backend sends `content-state` JSON built from
// the original five state fields, and ActivityKit decodes it with a default
// `JSONDecoder` (so `estimatedDeparture` is seconds since 2001, Foundation's
// default date encoding). Every field added since is optional with a nil
// default, which the synthesized decoder treats as "may be missing", so an
// older payload still decodes. Don't rename existing fields or status raw
// values, and don't add a custom date strategy.

import Foundation
import ActivityKit

// MARK: - Shared attribute & state

/// Static identity of a Live Activity: which flight it's about. Set once at
/// activity creation.
struct FlightActivityAttributes: ActivityAttributes {

    public typealias ContentState = FlightActivityState

    let flightNumber: String
    let airlineName: String
    let originIATA: String
    let destinationIATA: String
    let scheduledDeparture: Date

    // Added 2026-10 for the redesigned card. The widget can't see
    // `AirportCoordinates` or `AirportNames`, so the app resolves these when it
    // starts the activity. Nil (an older start, or an airport outside the
    // tables) falls back to the device zone and the spelled-out code.

    /// IANA zone of the origin airport, for the local departure time.
    var originTimeZoneID: String? = nil
    /// IANA zone of the destination airport, for the local arrival time.
    var destinationTimeZoneID: String? = nil
    /// What VoiceOver says for the origin ("Las Vegas").
    var originSpokenName: String? = nil
    /// What VoiceOver says for the destination ("Atlanta").
    var destinationSpokenName: String? = nil
}

/// Dynamic state that the system updates throughout the flight's life:
/// gate, status, countdown.
struct FlightActivityState: Codable, Hashable {
    var gate: String?
    var terminal: String?
    var status: FlightStatus
    var estimatedDeparture: Date
    var delayMinutes: Int?
    /// Added 2026-10. Nil when the booking carries no seat; shown as "—".
    var seat: String? = nil
    /// Added 2026-10. Gate arrival, scheduled or estimated. Nil shows "—".
    var estimatedArrival: Date? = nil

    /// `.scheduled` is the neutral starting state: it claims nothing about the
    /// flight beyond its timetable. Airline statuses (on time, delayed, …) are
    /// only set from live FlightAware data, never inferred from the clock.
    enum FlightStatus: String, Codable, CaseIterable {
        case scheduled, onTime, boarding, finalCall, delayed, departed, cancelled, diverted

        var label: String {
            switch self {
            case .scheduled:  return "Scheduled"
            case .onTime:     return "On Time"
            case .boarding:   return "Boarding"
            case .finalCall:  return "Final Call"
            case .delayed:    return "Delayed"
            case .departed:   return "Departed"
            case .cancelled:  return "Cancelled"
            case .diverted:   return "Diverted"
            }
        }

        var isUrgent: Bool {
            self == .finalCall || self == .delayed || self == .cancelled || self == .diverted
        }
    }
}
