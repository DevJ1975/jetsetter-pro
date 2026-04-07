// File: Features/FlightTracker/FlightTrackerViewModel.swift

import Foundation
import Combine

// MARK: - FlightTrackerViewModel

/// Handles all business logic and API calls for the Flight Tracker feature.
/// The view observes this object and only handles display.
@MainActor
final class FlightTrackerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var flights: [Flight] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var searchText: String = ""

    // MARK: - Private State

    /// Tracks the last searched ident to avoid duplicate requests
    private var lastSearchedIdent: String = ""

    // MARK: - Search

    /// Searches for flights by IATA or ICAO flight identifier (e.g. "AA100", "AAL100").
    /// Trims whitespace and uppercases the input before sending the request.
    func searchFlight(ident: String) async {
        let normalizedIdent = ident.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !normalizedIdent.isEmpty else {
            errorMessage = "Please enter a flight number."
            return
        }

        // Skip if we already have results for this ident
        guard normalizedIdent != lastSearchedIdent else { return }

        isLoading = true
        errorMessage = nil
        flights = []

        defer { isLoading = false }

        // ── Mock path ─────────────────────────────────────────────────────────
        if MockDataService.isEnabled {
            try? await Task.sleep(for: .milliseconds(900))
            flights = MockDataService.mockFlights
            lastSearchedIdent = normalizedIdent
            return
        }
        // ─────────────────────────────────────────────────────────────────────

        guard let url = Endpoints.FlightAware.flightStatus(ident: normalizedIdent) else {
            errorMessage = "Could not build the request URL."
            return
        }

        do {
            let response: FlightSearchResponse = try await APIClient.shared.get(
                url: url,
                headers: Endpoints.FlightAware.headers
            )
            flights = response.flights
            lastSearchedIdent = normalizedIdent

            if flights.isEmpty {
                errorMessage = "No flights found for \"\(normalizedIdent)\"."
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }

    // MARK: - Clear

    /// Resets the view to its empty search state.
    func clearSearch() {
        flights = []
        searchText = ""
        errorMessage = nil
        lastSearchedIdent = ""
    }
}
