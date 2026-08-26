// File: Features/FlightTracker/FlightTrackerViewModel.swift

import Foundation
import CoreLocation

// MARK: - FlightTrackerViewModel

@MainActor
@Observable
final class FlightTrackerViewModel {

    // MARK: - Observable State

    var flights: [Flight] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var searchText: String = ""

    /// Set whenever a successful response is received — drives the "Updated X ago" UI.
    var lastUpdated: Date? = nil

    /// The most recent live position of the tracked flight (drives the moving
    /// plane on the map). Nil until the first position sample arrives.
    var livePosition: FlightPosition? = nil

    /// The flown path so far — rendered as a solid trail behind the planned route.
    var track: [FlightPosition] = []

    // MARK: - Private State

    private var lastSearchedIdent: String = ""

    /// Background loop that refreshes `livePosition`/`track` while a detail
    /// screen for an airborne flight is on screen.
    private var livePollingTask: Task<Void, Never>?

    // MARK: - Search

    /// Searches for flights. Skips duplicate requests to avoid unnecessary API calls.
    func searchFlight(ident: String) async {
        let normalizedIdent = ident.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !normalizedIdent.isEmpty else {
            errorMessage = "Please enter a flight number."
            return
        }
        guard normalizedIdent != lastSearchedIdent else { return }

        await fetch(ident: normalizedIdent)
    }

    /// Refreshes the currently-displayed flight, bypassing the duplicate-search guard.
    func refresh() async {
        guard !lastSearchedIdent.isEmpty else { return }
        let ident = lastSearchedIdent
        lastSearchedIdent = ""          // reset so fetch() doesn't short-circuit
        await fetch(ident: ident)
    }

    // MARK: - Internal Fetch

    private func fetch(ident: String) async {
        isLoading = true
        errorMessage = nil
        flights = []

        defer { isLoading = false }

        guard let url = Endpoints.FlightAware.flightStatus(ident: ident) else {
            errorMessage = "Could not build the request URL."
            return
        }

        do {
            let response: FlightSearchResponse = try await APIClient.shared.get(
                url: url,
                headers: Endpoints.FlightAware.headers
            )
            flights = response.flights
            lastSearchedIdent = ident
            lastUpdated = Date()

            if flights.isEmpty {
                errorMessage = "No flights found for \"\(ident)\"."
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }

    // MARK: - Single-Flight Status Refresh

    /// Fetches the latest status for a single flight and returns the entry
    /// matching `faFlightId` (falling back to the first result). Used by the
    /// detail screen to keep gate/times/status/progress fresh without disturbing
    /// the shared list state (`flights`, `isLoading`, `errorMessage`). Returns
    /// nil on any failure so callers can keep showing the last-known snapshot.
    func fetchFlightStatus(ident: String, matching faFlightId: String) async -> Flight? {
        guard let url = Endpoints.FlightAware.flightStatus(ident: ident) else { return nil }
        do {
            let response: FlightSearchResponse = try await APIClient.shared.get(
                url: url,
                headers: Endpoints.FlightAware.headers
            )
            return response.flights.first { $0.faFlightId == faFlightId }
                ?? response.flights.first
        } catch {
            // Best-effort refresh: keep the last-known snapshot on failure.
            return nil
        }
    }

    // MARK: - Live Position Polling

    /// Begins refreshing the live position/track for an airborne flight. Safe to
    /// call repeatedly — restarts cleanly. Call `stopLivePolling()` on disappear.
    func startLivePolling(for flight: Flight, interval: TimeInterval = 45) {
        stopLivePolling()
        livePollingTask = Task { [weak self] in
            // First fetch happens immediately, then on the interval.
            while !Task.isCancelled {
                await self?.fetchPosition(for: flight)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopLivePolling() {
        livePollingTask?.cancel()
        livePollingTask = nil
    }

    private func fetchPosition(for flight: Flight) async {
        guard let url = Endpoints.FlightAware.flightTrack(ident: flight.faFlightId) else { return }
        do {
            let response: FlightTrackResponse = try await APIClient.shared.get(
                url: url,
                headers: Endpoints.FlightAware.headers
            )
            track = response.positions
            livePosition = response.positions.last
        } catch {
            // Position is best-effort; keep the last known sample and stay quiet.
        }
    }

    // MARK: - Clear

    func clearSearch() {
        stopLivePolling()
        flights = []
        searchText = ""
        errorMessage = nil
        lastSearchedIdent = ""
        lastUpdated = nil
        livePosition = nil
        track = []
    }
}
