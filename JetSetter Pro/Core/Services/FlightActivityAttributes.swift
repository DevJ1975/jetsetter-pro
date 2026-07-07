// File: Core/Services/FlightActivityAttributes.swift
//
// Shared Live Activity payload types. This file is the ONLY one that must be a
// member of BOTH the app target and the Widget Extension target — it has no
// dependencies beyond Foundation + ActivityKit, so it compiles cleanly in the
// extension. See SETUP-LIVE-ACTIVITY.md.

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
}

/// Dynamic state that the system updates throughout the flight's life:
/// gate, status, countdown.
struct FlightActivityState: Codable, Hashable {
    var gate: String?
    var terminal: String?
    var status: FlightStatus
    var estimatedDeparture: Date
    var delayMinutes: Int?

    enum FlightStatus: String, Codable, CaseIterable {
        case scheduled, onTime, boarding, finalCall, delayed, departed, cancelled

        var label: String {
            switch self {
            case .scheduled:  return "Scheduled"
            case .onTime:     return "On Time"
            case .boarding:   return "Boarding"
            case .finalCall:  return "Final Call"
            case .delayed:    return "Delayed"
            case .departed:   return "Departed"
            case .cancelled:  return "Cancelled"
            }
        }

        var isUrgent: Bool { self == .finalCall || self == .delayed || self == .cancelled }
    }
}
