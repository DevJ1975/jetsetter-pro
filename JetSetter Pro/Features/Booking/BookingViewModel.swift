// File: Features/Booking/BookingViewModel.swift

import Foundation

// MARK: - BookingViewModel

/// Manages hotel search state and Expedia API communication.
@MainActor
@Observable
final class BookingViewModel {

    // MARK: - Published State

    var searchParams = HotelSearchParams()
    var hotels: [HotelProperty] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var hasSearched: Bool = false

    // MARK: - Search Hotels

    /// Fetches hotel availability from Expedia Rapid using the current search
    /// parameters, authenticated with a fresh EAN signature header per request.
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

        // Resolve the free-text destination to an Expedia region_id before
        // searching. The availability endpoint only understands a region_id (or,
        // as a fallback below, free text) — without this step searches went out
        // with no destination and came back empty. Best-effort: on failure we
        // leave regionID blank and buildQueryItems() falls back to the raw text.
        if searchParams.regionID.isEmpty {
            if let regionID = await resolveRegionID(for: destination) {
                searchParams.regionID = regionID
            }
        }

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
            // EAN signature auth — the header is computed fresh (fresh timestamp)
            // for each request; Rapid Lodging does not use OAuth bearer tokens.
            let headers = ExpediaAuthService.shared.authorizationHeaders()

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

    // MARK: - Invalidate

    /// Clears stale result framing when the search inputs change without a new
    /// search being run. Returns the UI to the neutral "Find Your Stay" prompt
    /// rather than leaving the "No Hotels Found" placeholder from a prior run.
    /// No-op while a search is in flight so an active request isn't disturbed.
    func invalidateResults() {
        guard !isLoading else { return }
        guard hasSearched || !hotels.isEmpty || errorMessage != nil else { return }
        hotels = []
        errorMessage = nil
        hasSearched = false
    }

    // MARK: - Clear

    func clearSearch() {
        hotels = []
        errorMessage = nil
        hasSearched = false
        searchParams = HotelSearchParams()
    }

    // MARK: - Region Resolution

    /// Resolves a free-text destination (e.g. "Tokyo") to an Expedia
    /// `region_id` via the Rapid Geography region-search endpoint, so the
    /// availability search is actually scoped to somewhere. Best-effort: returns
    /// `nil` on any failure (endpoint unwired, credentials missing, no match) so
    /// the caller can fall back to sending the raw destination text.
    private func resolveRegionID(for destination: String) async -> String? {
        guard let url = Endpoints.Expedia.regionSearchURL(query: destination) else {
            return nil
        }

        do {
            // Same EAN signature auth as the availability search; APIClient's
            // credential guard surfaces `.notConfigured` when Expedia keys are
            // missing, which we swallow here to fall back to free-text search.
            let headers = ExpediaAuthService.shared.authorizationHeaders()
            let regions: [ExpediaRegion] = try await APIClient.shared.get(url: url, headers: headers)
            return regions.first.map(\.id)
        } catch {
            return nil
        }
    }

    // MARK: - Query Builder

    private func buildQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "checkin", value: searchParams.checkInString),
            URLQueryItem(name: "checkout", value: searchParams.checkOutString),
            URLQueryItem(name: "currency", value: searchParams.currency),
            URLQueryItem(name: "country_code", value: "US")
        ]

        // occupancy format: "adults-children" e.g. "2-0".
        // The availability endpoint expects one occupancy parameter per room,
        // so we repeat it `rooms` times; otherwise multi-room searches silently
        // collapse to single-room availability. Children are not yet part of the
        // search form, so they remain 0 for every room.
        let roomCount = max(1, searchParams.rooms)
        for _ in 0..<roomCount {
            items.append(URLQueryItem(name: "occupancy", value: "\(searchParams.adults)-0"))
        }

        // Use region_id when it's been resolved (searchHotels() runs the region
        // lookup before building this query); otherwise fall back to sending the
        // user's typed destination as free text so their input is never silently
        // dropped even if the region lookup failed or is unconfigured.
        if !searchParams.regionID.isEmpty {
            items.append(URLQueryItem(name: "region_id", value: searchParams.regionID))
        } else {
            let destination = searchParams.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            if !destination.isEmpty {
                items.append(URLQueryItem(name: "destination", value: destination))
            }
        }

        return items
    }
}
