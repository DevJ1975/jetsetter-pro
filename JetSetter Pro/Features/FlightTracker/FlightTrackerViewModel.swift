// File: Features/FlightTracker/FlightTrackerViewModel.swift

import Combine
import Foundation

// MARK: - FlightTrackerViewModel

@MainActor
final class FlightTrackerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var flights: [Flight] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var searchText: String = ""

    /// Set whenever a successful response is received — drives the "Updated X ago" UI.
    @Published var lastUpdated: Date? = nil

    // MARK: - Private State

    private var lastSearchedIdent: String = ""

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

        // ── Mock path ─────────────────────────────────────────────────────────
        if MockDataService.isEnabled {
            try? await Task.sleep(for: .milliseconds(900))
            flights = MockDataService.mockFlights
            lastSearchedIdent = ident
            lastUpdated = Date()
            return
        }
        // ─────────────────────────────────────────────────────────────────────

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

    // MARK: - Clear

    func clearSearch() {
        flights = []
        searchText = ""
        errorMessage = nil
        lastSearchedIdent = ""
        lastUpdated = nil
    }
}
