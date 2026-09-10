// File: Features/Booking/BookingViewModel.swift

import Foundation
import CoreLocation
import MapKit

// MARK: - BookingViewModel

/// Hotel search: hands off to a hotel site pre-filled with the form (§7.7,
/// in-app web) and lists hotels near the destination from Apple Maps.
@MainActor
@Observable
final class BookingViewModel {

    // MARK: - Published State

    var searchParams = HotelSearchParams()
    var nearbyHotels: [HotelPlace] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var hasSearched: Bool = false

    /// In-app web target (the hotel site, or a hotel's own page).
    var externalWebURL: URL?

    private let provider: HotelBookingProvider = .kayak
    var providerName: String { provider.displayName }

    // MARK: - Hand-off

    /// Opens the hotel site with destination, dates and guests already filled in.
    func openHotelSite() {
        guard validate() else { return }
        guard let url = provider.deepLinkURL(for: searchParams) else {
            errorMessage = "Could not build the search link. Please try again."
            return
        }
        externalWebURL = url
    }

    // MARK: - Nearby hotels (MapKit)

    /// Lists hotels around the destination so the traveler can browse and open a
    /// property's own site. Apple Maps has no rates, so none are shown.
    func findNearbyHotels() async {
        guard validate(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        nearbyHotels = []
        defer {
            isLoading = false
            hasSearched = true
        }

        let destination = searchParams.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let center = await resolve(destination) else {
            errorMessage = "Couldn't place \"\(destination)\" on the map. Try a city name or airport code."
            return
        }
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "hotels"
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 8_000, longitudinalMeters: 8_000)
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hotel])

        do {
            let response = try await MKLocalSearch(request: request).start()
            nearbyHotels = response.mapItems.compactMap { item -> HotelPlace? in
                guard let name = item.name else { return nil }
                let coordinate = item.placemark.coordinate
                return HotelPlace(
                    id: "\(name)|\(coordinate.latitude)|\(coordinate.longitude)",
                    name: name,
                    address: item.placemark.title ?? "",
                    coordinate: coordinate,
                    distanceMeters: origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)),
                    phoneNumber: item.phoneNumber,
                    websiteURL: item.url
                )
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            if nearbyHotels.isEmpty {
                errorMessage = "Apple Maps has no hotels listed near \"\(destination)\" yet."
            }
        } catch {
            errorMessage = "Couldn't look up hotels right now. Please try again."
        }
    }

    func open(_ hotel: HotelPlace) {
        externalWebURL = hotel.linkURL
    }

    // MARK: - Invalidate / Clear

    /// Clears stale results when the inputs change without a new search.
    func invalidateResults() {
        guard !isLoading else { return }
        guard hasSearched || !nearbyHotels.isEmpty || errorMessage != nil else { return }
        nearbyHotels = []
        errorMessage = nil
        hasSearched = false
    }

    func clearSearch() {
        nearbyHotels = []
        errorMessage = nil
        hasSearched = false
        searchParams = HotelSearchParams()
    }

    // MARK: - Helpers

    private func validate() -> Bool {
        errorMessage = nil
        guard !searchParams.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a destination."
            return false
        }
        guard searchParams.checkOutDate > searchParams.checkInDate else {
            errorMessage = "Check-out must be after check-in."
            return false
        }
        return true
    }

    private func resolve(_ query: String) async -> CLLocationCoordinate2D? {
        let upper = query.uppercased()
        if upper.count == 3, upper.allSatisfy(\.isLetter), let coordinate = AirportCoordinates.coordinate(for: upper) {
            return coordinate
        }
        return try? await CLGeocoder().geocodeAddressString(query).first?.location?.coordinate
    }
}
