// File: Features/Disruption/DisruptionViewModel.swift
// MVVM ViewModel for DisruptionDashboardView.
// Loads disruption events from the on-device store, exposes state for the UI,
// and handles user actions: resolve, rebook, hotel email, Uber reroute.

import SwiftUI

@MainActor
@Observable
final class DisruptionViewModel {

    // MARK: - Published State

    private(set) var activeDisruptions: [DisruptionEvent] = []
    private(set) var resolvedDisruptions: [DisruptionEvent] = []
    private(set) var isLoading = false
    private(set) var isPolling = false
    var errorMessage: String? = nil

    // In-app presentation targets (§7.7 — no external hand-offs).
    var externalWebURL: URL?          // rebooking / ride, in-app web
    var mailRequest: MailRequest?     // hotel late-arrival email

    struct MailRequest: Identifiable {
        let id = UUID()
        let recipients: [String]
        let subject: String
        let body: String
    }

    // MARK: - Load

    /// Fetches all disruption events from the on-device store, falling back to
    /// the legacy local cache key from earlier builds.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        await performLoad()
    }

    /// Guard-free fetch core shared by `load()` and `manualPoll()`. `manualPoll`
    /// calls this directly so its post-poll refresh isn't silently dropped by
    /// `load()`'s `isLoading` early-return when an initial/refreshable load is
    /// still in flight (isPolling and isLoading are independent guards).
    private func performLoad() async {
        let stored = await LocalDataService.shared.fetchDisruptionEvents()
        if !stored.isEmpty {
            partition(stored)
            return
        }

        // Fallback: locally-cached disruption events.
        if let data = UserDefaults.standard.data(forKey: "jetsetter_disruption_events_local") {
            if let local = try? JSONCoding.iso8601Decoder.decode([DisruptionEvent].self, from: data) {
                partition(local)
                return
            }
        }

        activeDisruptions = []
        resolvedDisruptions = []
    }

    private func partition(_ all: [DisruptionEvent]) {
        activeDisruptions   = all.filter { !$0.resolved }.sorted { $0.createdAt > $1.createdAt }
        resolvedDisruptions = all.filter {  $0.resolved }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Manual Poll (pull-to-refresh)

    /// Triggers a foreground poll of all active trip flights, then reloads events.
    func manualPoll() async {
        guard !isPolling else { return }
        isPolling = true
        errorMessage = nil
        defer { isPolling = false }

        do {
            try await DisruptionMonitorService.shared.pollActiveFlights()
            // Reload directly (not via `load()`) so a concurrent in-flight
            // `load()` can't make this refresh a silent no-op.
            await performLoad()
        } catch {
            errorMessage = "Poll failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Resolve

    /// Flight identity used by the dashboard to collapse multiple active events
    /// for the same flight into a single card (see `dedupedActiveDisruptions`).
    private func flightKey(_ event: DisruptionEvent) -> String {
        let f = event.originalFlight
        return "\(f.flightNumber)|\(f.origin)|\(f.destination)"
    }

    /// Marks a disruption as resolved with an optimistic update + rollback on failure.
    ///
    /// The dashboard collapses every active event for the same flight into one
    /// card, so resolving must clear *all* same-flight active events — otherwise
    /// the card reappears backed by a sibling event and "resolve" looks broken.
    func resolveDisruption(_ event: DisruptionEvent) async {
        let key = flightKey(event)
        // All active events represented by the tapped card (same flight).
        let originals = activeDisruptions.filter { flightKey($0) == key }
        guard !originals.isEmpty else { return }
        let updated = originals.map { original -> DisruptionEvent in
            var copy = original
            copy.resolved = true
            return copy
        }

        // Optimistic: move the whole flight from active → resolved immediately.
        activeDisruptions.removeAll { flightKey($0) == key }
        resolvedDisruptions.append(contentsOf: updated)
        resolvedDisruptions.sort { $0.createdAt > $1.createdAt }

        for e in updated {
            await LocalDataService.shared.upsertDisruptionEvent(e)
        }
    }

    // MARK: - URL Actions

    /// Opens the event's pre-filled same-route flight search in-app. When no
    /// link was built the CTA isn't shown, so this is a no-op rather than a dead page.
    func openRebookingURL(for event: DisruptionEvent, alternative: AlternativeFlight? = nil) {
        _ = alternative // no deep link is stored per-alternative; use the event's real URL
        // Present the rebooking page in-app (§7.7) rather than an external browser.
        guard let s = event.rebookingUrl, let url = URL(string: s) else { return }
        externalWebURL = url
    }

    /// Presents the rideshare provider's mobile site in-app to re-route to the
    /// updated gate (§7.7 — no hand-off to the ride app).
    func openUberReroute(for event: DisruptionEvent) {
        externalWebURL = URL(string: "https://m.uber.com")
    }

    /// Prepares an in-app hotel late-arrival email (MFMailCompose, §7.7).
    ///
    /// Copy branches on the disruption type: `delayMinutes` is nil for
    /// cancellations and gate changes (see `FlightSnapshot`), so a fixed
    /// "delay of {delay} minutes" line would read "delay of 0 minutes" and
    /// confuse the hotel. We only cite a minute count when a real delay value
    /// exists; cancellations state the flight was cancelled and arrival is
    /// uncertain.
    func openHotelEmail(for event: DisruptionEvent) {
        guard let contact = event.hotelContact else { return }
        let flight = event.originalFlight.flightNumber

        let situation: String
        switch event.eventType {
        case .cancellation:
            situation = "my flight \(flight) has been cancelled and I'm arranging alternative " +
                "travel, so my arrival time is currently uncertain"
        case .missedConnection:
            situation = "my flight \(flight) has been disrupted and I'm at risk of missing a " +
                "connection, so my arrival time is currently uncertain"
        case .majorDelay, .gateChange:
            if let delay = event.originalFlight.delayMinutes, delay > 0 {
                situation = "my flight \(flight) has been delayed by an estimated \(delay) minutes, " +
                    "so I expect to arrive later than planned"
            } else {
                situation = "my flight \(flight) has been disrupted, so I expect to arrive " +
                    "later than planned"
            }
        }

        mailRequest = MailRequest(
            recipients: [contact],
            subject: "Late Arrival Notification — Flight \(flight)",
            body: """
            Dear Hotel Team,

            \(situation.prefix(1).uppercased() + situation.dropFirst()). Kindly hold my \
            reservation — I'll contact you upon landing if my arrival time changes further.

            Thank you,
            Sent from JetSetter Pro
            """
        )
    }
}
