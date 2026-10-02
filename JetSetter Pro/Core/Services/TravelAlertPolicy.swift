// File: Core/Services/TravelAlertPolicy.swift
//
// How loudly each kind of travel alert is allowed to interrupt, and what the
// announcement voice says for each disruption. Kept as pure data so tests pin
// the rules; the schedulers in NotificationManager, CheckInService and
// DisruptionMonitorService only look the answers up.
//
// Interruption levels: an alert is time-sensitive (breaks through Focus and
// the notification summary) only when the traveler has to act within minutes
// or miss something: a gate change, a cancellation, a diversion, boarding,
// leaving for the airport, check-in opening. A delay or a tight connection is
// `.active`: it still sounds, but a traveler in a "Sleep" Focus at 5 a.m.
// isn't woken for a 50-minute delay. Time-sensitive delivery needs the Time
// Sensitive Notifications capability on the App ID (the entitlement is in
// JetSetter Pro.entitlements); without it iOS delivers these as `.active`.

import Foundation
import UserNotifications

// MARK: - Alert kinds

nonisolated enum TravelAlertKind: String, CaseIterable, Sendable {
    // Time-sensitive.
    case gateChange, cancellation, diversion, boarding, leaveNow, checkInOpen
    // Active.
    case delay, connectionAtRisk, tripReminder, expenseReminder, lovedOnes

    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .gateChange, .cancellation, .diversion, .boarding, .leaveNow, .checkInOpen:
            return .timeSensitive
        case .delay, .connectionAtRisk, .tripReminder, .expenseReminder, .lovedOnes:
            return .active
        }
    }

    init(_ disruption: DisruptionType) {
        switch disruption {
        case .gateChange:       self = .gateChange
        case .cancellation:     self = .cancellation
        case .diversion:        self = .diversion
        case .majorDelay:       self = .delay
        case .missedConnection: self = .connectionAtRisk
        }
    }

    /// The backend's `alertType` push key. Accepts its snake_case values
    /// ("gate_change", the `DisruptionType` raw values) and camelCase
    /// ("gateChange") alike, since both have shipped in payloads.
    init?(alertType: String?) {
        guard let key = alertType?.lowercased().filter(\.isLetter), !key.isEmpty else { return nil }
        switch key {
        case "gatechange":                                  self = .gateChange
        case "cancellation", "cancelled", "canceled":       self = .cancellation
        case "diversion", "diverted":                       self = .diversion
        case "boarding", "boardingsoon", "finalcall":       self = .boarding
        case "leavenow", "leaveby", "timetoleave":          self = .leaveNow
        case "checkinopen", "checkin":                      self = .checkInOpen
        case "delay", "delayed", "majordelay":              self = .delay
        case "missedconnection", "connectionatrisk":        self = .connectionAtRisk
        default:                                            return nil
        }
    }
}

// MARK: - Disruption announcements

nonisolated enum DisruptionAnnouncement {

    /// What the announcement voice says for a disruption alert.
    ///
    /// `airline` is left empty everywhere: the flight number carries its own
    /// designator, which `AnnouncementScript` prefers (and on a codeshare it is
    /// the number the traveler was alerted about).
    ///
    /// A delay needs the new departure time *and* the origin airport's zone,
    /// because the time is spoken as the board at that airport shows it. When
    /// either is unknown the result is a delay the script can't speak exactly
    /// (no flight to name), so `AnnouncementScript` falls back, by its own
    /// rule, to "Flight is delayed. Please check the app for details." Saying
    /// a time in the phone's zone would be worse than saying none.
    static func announcement(
        for alert: DisruptionAlert,
        flightNumber: String,
        newDeparture: Date?,
        originTimeZone: TimeZone?
    ) -> Announcement {
        switch alert.type {
        case .gateChange:
            return .gateChange(airline: "", flight: flightNumber, gate: alert.value)
        case .majorDelay:
            guard let newDeparture, let originTimeZone else { return delayWithoutTime }
            return .delay(airline: "", flight: flightNumber, newDeparture: newDeparture, timeZone: originTimeZone)
        case .cancellation:
            return .cancelled(airline: "", flight: flightNumber)
        case .diversion:
            return .diverted(airline: "", flight: flightNumber)
        case .missedConnection:
            return .connectionAtRisk
        }
    }

    /// A delay that resolves to the generic script (see above).
    static let delayWithoutTime = Announcement.delay(
        airline: "", flight: "", newDeparture: Date(timeIntervalSince1970: 0), timeZone: .gmt
    )
}
