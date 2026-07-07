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

    /// Fallback that auto-ends the card a while after the flight should have
    /// arrived, so it never lingers indefinitely when `.arrived` is never detected
    /// (e.g. no GPS/window seat). Cancelled/replaced whenever the activity changes.
    private var autoEndTask: Task<Void, Never>?

    /// How long after the (estimated) arrival the card is allowed to remain before
    /// the fallback tears it down.
    private let postArrivalGrace: TimeInterval = 45 * 60

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
        initialStatus: FlightActivityState.FlightStatus = .scheduled,
        scheduledArrival: Date? = nil
    ) -> Activity<FlightActivityAttributes>? {
        guard isAvailable else { return nil }

        // If an activity for the SAME flight is already live, keep it (avoids a
        // visible teardown/recreate flicker on re-entry) and just return it.
        if let existing = current, existing.attributes.flightNumber == flightNumber {
            return existing
        }

        // End any existing activity for a different flight first to avoid duplicates.
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

        // Prefer keying the stale window to the real arrival estimate: a long-haul
        // needs the card through touchdown (a fixed departure+4h would dim it
        // mid-flight), while a short hop shouldn't linger for hours. Fall back to
        // departure+4h only when no arrival estimate is available.
        let staleDate = staleDate(scheduledDeparture: scheduledDeparture, scheduledArrival: scheduledArrival)
        let content = ActivityContent(state: state, staleDate: staleDate)
        do {
            let activity = try Activity.request(attributes: attributes, content: content)
            current = activity
            scheduleAutoEnd(scheduledDeparture: scheduledDeparture, scheduledArrival: scheduledArrival)
            return activity
        } catch {
            // Request failed; drop the reference to the now-ended previous
            // activity so a later update() doesn't target a dead activity.
            current = nil
            return nil
        }
    }

    /// Stale window keyed to the estimated arrival plus a grace period when known,
    /// otherwise the legacy departure+4h heuristic.
    private func staleDate(scheduledDeparture: Date, scheduledArrival: Date?) -> Date {
        if let arrival = scheduledArrival {
            return arrival.addingTimeInterval(postArrivalGrace)
        }
        return scheduledDeparture.addingTimeInterval(4 * 3600)
    }

    /// Arms a fallback that ends the card a while after the flight should have
    /// arrived. `.arrived` detection (InFlightTrackingService) still ends it
    /// earlier when it fires; this only covers the case where it never does.
    private func scheduleAutoEnd(scheduledDeparture: Date, scheduledArrival: Date?) {
        autoEndTask?.cancel()
        let deadline = staleDate(scheduledDeparture: scheduledDeparture, scheduledArrival: scheduledArrival)
        let interval = deadline.timeIntervalSinceNow
        guard interval > 0 else { return }
        autoEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.end()
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
        // Anchor the stale window to "now" so a status update that arrives after
        // the (estimated) departure — common for post-departure/arrival
        // disruptions — doesn't produce an already-elapsed staleDate that iOS
        // immediately dims.
        let staleAnchor = max(Date(), estimatedDeparture)
        let content = ActivityContent(state: state, staleDate: staleAnchor.addingTimeInterval(4 * 3600))

        // Terminal statuses: push the final state, then dismiss shortly after so
        // the card doesn't linger for the full 4h stale window.
        if status == .departed || status == .cancelled {
            Task {
                await activity.update(content)
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
            }
            autoEndTask?.cancel()
            autoEndTask = nil
            current = nil
        } else {
            Task { await activity.update(content) }
        }
    }

    /// Removes the activity from the Lock Screen / Dynamic Island. Call when
    /// the flight has departed and the user no longer needs it visible.
    func end() {
        autoEndTask?.cancel()
        autoEndTask = nil
        guard let activity = current else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        current = nil
    }
}
