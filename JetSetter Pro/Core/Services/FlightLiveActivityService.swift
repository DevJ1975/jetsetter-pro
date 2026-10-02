// File: Core/Services/FlightLiveActivityService.swift
//
// ActivityKit-backed Live Activity for active flights. The shared attribute /
// state types live in `FlightActivityAttributes.swift` so they can be added to
// BOTH this app target and the WidgetKit extension without dragging this
// service into the widget (see SETUP-LIVE-ACTIVITY.md). Without the widget
// extension, calls to start/update silently no-op — the main target still
// compiles.
//
// Two past defects shape this file:
//  • The card started at check-in, often 24 h before departure. iOS ends a
//    Live Activity after at most 8 hours, so it was gone before the flight.
//    `start` now only runs within `startWindow` of departure; `startIfDue(for:)`
//    is the hook for starting it later from a foreground screen.
//  • `current` lived only in memory. After any relaunch (including the
//    background relaunch a disruption poll causes) update/end silently no-op'd
//    while the card was still on the Lock Screen, and the next `start` stacked
//    a duplicate. Every entry point now re-adopts the running activity first.

import Foundation
import ActivityKit

// MARK: - Service

@MainActor
final class FlightLiveActivityService {

    static let shared = FlightLiveActivityService()
    private init() {
        adoptRunningActivity()
    }

    /// The current activity. Only one at a time is supported in this MVP.
    /// Re-adopted from `Activity.activities` whenever it's nil or ended.
    private var current: Activity<FlightActivityAttributes>?

    /// Fallback that auto-ends the card a while after the flight should have
    /// arrived, so it never lingers indefinitely when `.arrived` is never detected
    /// (e.g. no GPS/window seat). Cancelled/replaced whenever the activity changes.
    private var autoEndTask: Task<Void, Never>?

    /// How long after the (estimated) arrival the card is allowed to remain before
    /// the fallback tears it down.
    private let postArrivalGrace: TimeInterval = 45 * 60

    /// How close to departure a card may start. iOS ends a Live Activity after
    /// at most 8 hours; starting 4 h out keeps it alive through boarding,
    /// pushback and the first hours of the flight.
    static let startWindow: TimeInterval = 4 * 3600

    /// True when the user's device supports Live Activities and they're enabled.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// True when a card for a flight departing at `departure` should exist now:
    /// within `startWindow` of departure and not more than an hour past it.
    static func isDue(departure: Date, now: Date = Date()) -> Bool {
        let lead = departure.timeIntervalSince(now)
        return lead <= startWindow && lead > -3600
    }

    // MARK: - Lifecycle

    /// Starts a Live Activity for the supplied flight. Replaces any active one.
    /// Returns nil without starting anything when departure is further away
    /// than `startWindow`: the card would expire before the flight.
    ///
    /// `initialStatus` defaults to the neutral `.scheduled`. Pass an airline
    /// status only when it comes from live data.
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
        guard isAvailable, Self.isDue(departure: scheduledDeparture) else { return nil }
        adoptRunningActivity()

        // If an activity for the SAME flight is already live, keep it (avoids a
        // visible teardown/recreate flicker on re-entry) and just return it.
        if let existing = current,
           Self.sameFlight(existing.attributes.flightNumber, flightNumber) {
            return existing
        }

        // End any existing activity for a different flight first to avoid duplicates.
        if let existing = current {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
            current = nil
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
            scheduleAutoEnd(at: staleDate)
            return activity
        } catch {
            // Request failed; drop the reference to the now-ended previous
            // activity so a later update() doesn't target a dead activity.
            current = nil
            return nil
        }
    }

    /// Starts the card for an itinerary flight if it departs within
    /// `startWindow`; otherwise does nothing. Intended for a foreground hook
    /// (e.g. Home's load) so a traveler who checked in a day early still gets
    /// the card on departure day. ActivityKit only allows starting from the
    /// foreground, so don't call this from a background task.
    @discardableResult
    func startIfDue(for item: ItineraryItem) -> Activity<FlightActivityAttributes>? {
        guard item.type == .flight, Self.isDue(departure: item.startDate) else { return nil }
        let details = item.flightDetails
        guard let flightNumber = TravelStore.extractFlightNumber(from: details?.flightNumber ?? "")
                ?? TravelStore.extractFlightNumber(from: item.title)
        else { return nil }

        // Unknown fields stay empty or nil (rendered as blank / no gate), never guessed.
        func known(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespaces),
                  !trimmed.isEmpty, trimmed != "—" else { return nil }
            return trimmed
        }
        return start(
            flightNumber: flightNumber,
            airline: known(details?.airline)
                ?? known(item.bookingProvider)
                ?? TravelStore.airlineDesignator(from: flightNumber),
            originIATA: known(details?.originCode)?.uppercased() ?? "",
            destinationIATA: known(details?.destinationCode)?.uppercased() ?? "",
            scheduledDeparture: item.startDate,
            gate: known(details?.gate),
            terminal: known(details?.terminal),
            initialStatus: .scheduled,
            scheduledArrival: item.endDate
        )
    }

    /// Stale window keyed to the estimated arrival plus a grace period when known,
    /// otherwise the legacy departure+4h heuristic.
    private func staleDate(scheduledDeparture: Date, scheduledArrival: Date?) -> Date {
        if let arrival = scheduledArrival {
            return arrival.addingTimeInterval(postArrivalGrace)
        }
        return scheduledDeparture.addingTimeInterval(4 * 3600)
    }

    /// Arms a fallback that ends the card at `deadline`. `.arrived` detection
    /// (InFlightTrackingService) still ends it earlier when it fires; this only
    /// covers the case where it never does.
    private func scheduleAutoEnd(at deadline: Date) {
        autoEndTask?.cancel()
        autoEndTask = nil
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
    ///
    /// Pass `flightNumber` (and ideally `scheduledDeparture`) whenever the
    /// caller knows which flight the update is about: the monitor polls every
    /// flight on the itinerary, and an update for the return leg must never
    /// repaint the outbound flight's card. Omitted, the update applies to
    /// whatever card is showing (InFlightTrackingService's behaviour).
    func update(
        forFlight flightNumber: String? = nil,
        departing scheduledDeparture: Date? = nil,
        gate: String? = nil,
        terminal: String? = nil,
        status: FlightActivityState.FlightStatus,
        estimatedDeparture: Date,
        delayMinutes: Int? = nil
    ) {
        adoptRunningActivity()
        guard let activity = current else { return }
        if let flightNumber,
           !Self.sameFlight(activity.attributes.flightNumber, flightNumber) { return }
        // Same flight number on a different day is a different flight.
        if let scheduledDeparture,
           abs(activity.attributes.scheduledDeparture.timeIntervalSince(scheduledDeparture)) > 12 * 3600 { return }

        let state = FlightActivityState(
            gate: gate ?? activity.content.state.gate,
            terminal: terminal ?? activity.content.state.terminal,
            status: status,
            estimatedDeparture: estimatedDeparture,
            delayMinutes: delayMinutes
        )
        // Nothing changed: skip the update so repeated polls don't spend the
        // activity's update budget.
        if state == activity.content.state { return }

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
        adoptRunningActivity()
        guard let activity = current else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        current = nil
    }

    // MARK: - Relaunch recovery

    /// Points `current` at the activity iOS is still showing for us, if any.
    /// A relaunch wipes `current` but not the card, so without this update/end
    /// would no-op and start would stack a duplicate. Earlier builds could
    /// already have stacked duplicates; any extras are ended here.
    private func adoptRunningActivity() {
        if let current, Self.isRunning(current) { return }
        let running = Activity<FlightActivityAttributes>.activities.filter { Self.isRunning($0) }
        current = running.first
        for extra in running.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
        // Re-arm the fallback end for an adopted card; the original timer died
        // with the previous process.
        if autoEndTask == nil, let adopted = current, let stale = adopted.content.staleDate {
            scheduleAutoEnd(at: stale)
        }
    }

    private static func isRunning(_ activity: Activity<FlightActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .stale: return true
        default:              return false
        }
    }

    /// Flight numbers arrive from several sources ("DL1423", "DL 1423"), so
    /// compare them with spaces removed and case folded.
    private static func sameFlight(_ lhs: String, _ rhs: String) -> Bool {
        func canonical(_ s: String) -> String {
            s.uppercased().filter { !$0.isWhitespace }
        }
        return canonical(lhs) == canonical(rhs)
    }
}
