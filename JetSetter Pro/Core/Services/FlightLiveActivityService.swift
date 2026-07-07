// File: Core/Services/FlightLiveActivityService.swift
//
// ActivityKit-backed Live Activity for active flights. The shared attribute /
// state types live in `FlightActivityAttributes.swift` so they can be added to
// BOTH this app target and the WidgetKit extension without dragging this
// service into the widget (see SETUP-LIVE-ACTIVITY.md). Without the widget
// extension, calls to start/update silently no-op — the main target still
// compiles.

import Foundation
import ActivityKit

// MARK: - Service

@MainActor
final class FlightLiveActivityService {

    static let shared = FlightLiveActivityService()
    private init() {}

    /// The current activity. Only one at a time is supported in this MVP.
    private var current: Activity<FlightActivityAttributes>?

    /// True when the user's device supports Live Activities and they're enabled.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Lifecycle

    /// Starts a Live Activity for the supplied flight. Replaces any active one.
    @discardableResult
    func start(
        flightNumber: String,
        airline: String,
        originIATA: String,
        destinationIATA: String,
        scheduledDeparture: Date,
        gate: String?,
        terminal: String?,
        initialStatus: FlightActivityState.FlightStatus = .scheduled
    ) -> Activity<FlightActivityAttributes>? {
        guard isAvailable else { return nil }

        // End any existing activity for this flight first to avoid duplicates.
        if let existing = current {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }

        let attributes = FlightActivityAttributes(
            flightNumber: flightNumber,
            airlineName: airline,
            originIATA: originIATA,
            destinationIATA: destinationIATA,
            scheduledDeparture: scheduledDeparture
        )
        let state = FlightActivityState(
            gate: gate,
            terminal: terminal,
            status: initialStatus,
            estimatedDeparture: scheduledDeparture,
            delayMinutes: nil
        )

        let content = ActivityContent(state: state, staleDate: scheduledDeparture.addingTimeInterval(4 * 3600))
        do {
            let activity = try Activity.request(attributes: attributes, content: content)
            current = activity
            return activity
        } catch {
            return nil
        }
    }

    /// Pushes a new state to the active activity. Use this when DisruptionMonitorService
    /// detects gate changes, delays, or status transitions.
    func update(
        gate: String? = nil,
        terminal: String? = nil,
        status: FlightActivityState.FlightStatus,
        estimatedDeparture: Date,
        delayMinutes: Int? = nil
    ) {
        guard let activity = current else { return }
        let state = FlightActivityState(
            gate: gate ?? activity.content.state.gate,
            terminal: terminal ?? activity.content.state.terminal,
            status: status,
            estimatedDeparture: estimatedDeparture,
            delayMinutes: delayMinutes
        )
        let content = ActivityContent(state: state, staleDate: estimatedDeparture.addingTimeInterval(4 * 3600))
        Task { await activity.update(content) }
    }

    /// Removes the activity from the Lock Screen / Dynamic Island. Call when
    /// the flight has departed and the user no longer needs it visible.
    func end() {
        guard let activity = current else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        current = nil
    }
}
