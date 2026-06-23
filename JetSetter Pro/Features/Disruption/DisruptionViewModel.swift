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
        if let remote = try? await FirebaseService.shared.fetchDisruptionEvents(), !remote.isEmpty {
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
            try await FirebaseService.shared.upsertDisruptionEvent(updated)
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
        guard let s = urlString, let url = URL(string: s) else { return }
        UIApplication.shared.open(url)
    }

    /// Opens the Uber deep link pre-filled with the disrupted flight's updated gate.
    func openUberReroute(for event: DisruptionEvent) {
        guard let s = event.uberDeepLink, let url = URL(string: s) else { return }
        UIApplication.shared.open(url)
    }

    /// Builds and opens the hotel late-arrival mailto link.
    func openHotelEmail(for event: DisruptionEvent) async {
        guard let contact = event.hotelContact else { return }
        guard let url = await DisruptionResponseEngine.shared.buildHotelLateArrivalMailtoURL(
            contactEmail: contact,
            flightNumber: event.originalFlight.flightNumber,
            originalDeparture: event.originalFlight.scheduledDeparture,
            delayMinutes: event.originalFlight.delayMinutes ?? 0
        ) else { return }
        await UIApplication.shared.open(url)
    }
}
