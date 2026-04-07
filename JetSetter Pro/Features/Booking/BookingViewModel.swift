// File: Features/Booking/BookingViewModel.swift

import Foundation
import Combine

// MARK: - BookingViewModel

/// Manages hotel search state and Expedia API communication.
@MainActor
final class BookingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var searchParams = HotelSearchParams()
    @Published var hotels: [HotelProperty] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasSearched: Bool = false

    // MARK: - Search Hotels

    /// Fetches hotel availability from Expedia using the current search parameters.
    /// Acquires a fresh OAuth token automatically before the request.
    func searchHotels() async {
        let destination = searchParams.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            errorMessage = "Please enter a destination."
            return
        }

        isLoading = true
        errorMessage = nil
        hotels = []
        // Note: hasSearched is NOT reset here — avoids a false→true flicker that
        // causes the "No results" placeholder to flash during re-searches.

        defer {
            isLoading = false
            hasSearched = true
        }

        // ── Mock path ─────────────────────────────────────────────────────────
        if MockDataService.isEnabled {
            try? await Task.sleep(for: .milliseconds(1_200))
            hotels = MockDataService.mockHotels
            return
        }
        // ─────────────────────────────────────────────────────────────────────

        guard let baseURL = Endpoints.Expedia.propertyAvailabilityURL else {
            errorMessage = "Could not build the request URL."
            return
        }

        // Build query parameters
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = buildQueryItems()

        guard let url = components?.url else {
            errorMessage = "Could not build the search URL."
            return
        }

        do {
            // Fetch a valid OAuth token (uses cache when still valid)
            let token = try await ExpediaAuthService.shared.validToken()
            let headers = Endpoints.Expedia.bearerHeaders(token: token)

            hotels = try await APIClient.shared.get(url: url, headers: headers)

            if hotels.isEmpty {
                errorMessage = "No hotels found for \"\(destination)\". Try different dates or a broader destination."
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Search failed. Please try again."
        }
    }

    // MARK: - Clear

    func clearSearch() {
        hotels = []
        errorMessage = nil
        hasSearched = false
        searchParams = HotelSearchParams()
    }

    // MARK: - Query Builder

    private func buildQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "checkin", value: searchParams.checkInString),
            URLQueryItem(name: "checkout", value: searchParams.checkOutString),
            URLQueryItem(name: "currency", value: searchParams.currency),
            URLQueryItem(name: "country_code", value: "US"),
            // occupancy format: "adults-children" e.g. "2-0"
            URLQueryItem(name: "occupancy", value: "\(searchParams.adults)-0")
        ]

        // Use region_id if resolved; otherwise pass destination as free text
        // TODO: Add a region lookup step to resolve destination text → region_id
        if !searchParams.regionID.isEmpty {
            items.append(URLQueryItem(name: "region_id", value: searchParams.regionID))
        }

        return items
    }
}
