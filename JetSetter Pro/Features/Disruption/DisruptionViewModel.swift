// File: Features/Disruption/DisruptionViewModel.swift
// MVVM ViewModel for DisruptionDashboardView.
// Loads disruption events from Firebase, exposes state for the UI,
// and handles user actions: resolve, rebook, hotel email, Uber reroute.

import SwiftUI
import Combine

@MainActor
final class DisruptionViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var activeDisruptions: [DisruptionEvent] = []
    @Published private(set) var resolvedDisruptions: [DisruptionEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPolling = false
    @Published var errorMessage: String? = nil

    // In-app presentation targets (§7.7 — no external hand-offs).
    @Published var externalWebURL: URL?          // rebooking / ride, in-app web
    @Published var mailRequest: MailRequest?     // hotel late-arrival email

    struct MailRequest: Identifiable {
        let id = UUID()
        let recipients: [String]
        let subject: String
        let body: String
    }

    // MARK: - Load

    /// Fetches all disruption events. Tries Firebase first; falls back to the
    /// local UserDefaults seed (`jetsetter_disruption_events_local`) so the
    /// dashboard shows seeded demo data when the user isn't signed in.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Try authenticated backend fetch first.
        if let remote = try? await SupabaseService.shared.fetchDisruptionEvents(), !remote.isEmpty {
            partition(remote)
            return
        }

        // Fallback: local seed (used by demo mode / first-launch demo).
        if let data = UserDefaults.standard.data(forKey: DemoSeeder.disruptionEventsLocalKey) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            if let local = try? decoder.decode([DisruptionEvent].self, from: data) {
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
            await load()
        } catch {
            errorMessage = "Poll failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Resolve

    /// Marks a disruption event as resolved with an optimistic update + rollback on failure.
    func resolveDisruption(_ event: DisruptionEvent) async {
        var updated = event
        updated.resolved = true

        // Optimistic: move from active → resolved immediately
        activeDisruptions.removeAll   { $0.id == event.id }
        resolvedDisruptions.insert(updated, at: 0)

        do {
            try await SupabaseService.shared.upsertDisruptionEvent(updated)
        } catch {
            // Rollback: restore original position
            resolvedDisruptions.removeAll { $0.id == event.id }
            activeDisruptions.insert(event, at: 0)
            errorMessage = "Could not resolve: \(error.localizedDescription)"
        }
    }

    // MARK: - URL Actions

    /// Opens the Amadeus / Duffel booking page for the chosen alternative flight.
    func openRebookingURL(for event: DisruptionEvent, alternative: AlternativeFlight? = nil) {
        // Prefer the URL for the explicitly chosen alternative; fall back to the event's stored URL.
        let urlString: String?
        if let token = alternative?.bookingToken {
            urlString = "https://www.amadeus.com/offers/\(token)"
        } else {
            urlString = event.rebookingUrl
        }
        // Present the rebooking page in-app (§7.7) rather than an external browser.
        guard let s = urlString, let url = URL(string: s) else { return }
        externalWebURL = url
    }

    /// Presents the rideshare provider's mobile site in-app to re-route to the
    /// updated gate (§7.7 — no hand-off to the ride app).
    func openUberReroute(for event: DisruptionEvent) {
        externalWebURL = URL(string: "https://m.uber.com")
    }

    /// Prepares an in-app hotel late-arrival email (MFMailCompose, §7.7).
    func openHotelEmail(for event: DisruptionEvent) {
        guard let contact = event.hotelContact else { return }
        let flight = event.originalFlight.flightNumber
        let delay = event.originalFlight.delayMinutes ?? 0
        mailRequest = MailRequest(
            recipients: [contact],
            subject: "Late Arrival Notification — Flight \(flight)",
            body: """
            Dear Hotel Team,

            My flight \(flight) has been disrupted with an estimated delay of \(delay) minutes, \
            so I expect to arrive later than planned. Kindly hold my reservation — I'll contact \
            you upon landing if my arrival time changes further.

            Thank you,
            Sent from JetSetter Pro
            """
        )
    }
}
