// File: Features/GroundTransport/GroundTransportViewModel.swift

import Foundation
import Combine
import CoreLocation
import UIKit

// MARK: - GroundTransportViewModel

/// Manages location detection, ride estimate fetching from Uber and Lyft,
/// and deep-link dispatch to the respective ride apps.
@MainActor
final class GroundTransportViewModel: ObservableObject {

    // MARK: - Published State

    @Published var pickupLocation: CLLocation? = nil
    @Published var pickupAddress: String = "Detecting location…"
    @Published var dropoffAddress: String = ""
    @Published var rideOptions: [RideOption] = []
    @Published var isLocating: Bool = false
    @Published var isLoadingEstimates: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasSearched: Bool = false

    // MARK: - Cached Lyft Token

    private var lyftToken: String? = nil
    private var lyftTokenExpiry: Date? = nil

    // MARK: - Init

    init() {
        Task { await detectCurrentLocation() }
    }

    // MARK: - Location Detection

    /// Uses LocationService to get the device's current coordinates as the pickup point.
    func detectCurrentLocation() async {
        guard !isLocating else { return }  // Prevent concurrent location detections
        isLocating = true
        errorMessage = nil
        pickupAddress = "Detecting location…"

        defer { isLocating = false }

        // ── Mock path ─────────────────────────────────────────────────────────
        if MockDataService.isEnabled {
            try? await Task.sleep(for: .milliseconds(600))
            pickupAddress = "O'Hare International Airport, Chicago, IL"
            pickupLocation = CLLocation(latitude: 41.9742, longitude: -87.9073)
            return
        }
        // ─────────────────────────────────────────────────────────────────────

        do {
            let location = try await LocationService.shared.requestCurrentLocation()
            pickupLocation = location
            // Reverse geocode to get a human-readable address
            pickupAddress = await reverseGeocode(location: location)
        } catch let error as LocationError {
            pickupAddress = "Location unavailable"
            errorMessage = error.errorDescription
        } catch {
            pickupAddress = "Location unavailable"
        }
    }

    // MARK: - Reverse Geocode

    private func reverseGeocode(location: CLLocation) async -> String {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let components = [
                    placemark.name,
                    placemark.locality,
                    placemark.administrativeArea
                ].compactMap { $0 }
                return components.joined(separator: ", ")
            }
        } catch {
            // Fall back to coordinate string on geocoding failure
        }
        return location.coordinateString
    }

    // MARK: - Fetch Estimates

    /// Fetches ride estimates from both Uber and Lyft in parallel for the current route.
    func fetchEstimates() async {
        guard !isLoadingEstimates else { return }  // Prevent concurrent estimate fetches
        let dropoff = dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dropoff.isEmpty else {
            errorMessage = "Please enter a dropoff destination."
            return
        }
        guard let pickup = pickupLocation else {
            errorMessage = "Pickup location is not available yet. Please wait or tap the location button."
            return
        }

        isLoadingEstimates = true
        errorMessage = nil
        rideOptions = []
        hasSearched = false

        defer {
            isLoadingEstimates = false
            hasSearched = true
        }

        // ── Mock path ─────────────────────────────────────────────────────────
        if MockDataService.isEnabled {
            try? await Task.sleep(for: .milliseconds(800))
            rideOptions = MockDataService.mockRideOptions
            return
        }
        // ─────────────────────────────────────────────────────────────────────

        // Geocode the dropoff address to get coordinates
        guard let dropoffLocation = await geocode(address: dropoff) else {
            errorMessage = "Could not find \"\(dropoff)\". Please try a more specific address."
            return
        }

        // Fetch from both providers concurrently
        async let uberOptions = fetchUberEstimates(from: pickup, to: dropoffLocation)
        async let lyftOptions = fetchLyftEstimates(from: pickup, to: dropoffLocation)

        let (uber, lyft) = await (uberOptions, lyftOptions)
        rideOptions = uber + lyft

        if rideOptions.isEmpty {
            errorMessage = "No rides available for this route. Try a different destination."
        }
    }

    // MARK: - Uber Estimates

    private func fetchUberEstimates(from pickup: CLLocation, to dropoff: CLLocation) async -> [RideOption] {
        guard let url = Endpoints.Uber.priceEstimatesURL(
            startLatitude:  pickup.coordinate.latitude,
            startLongitude: pickup.coordinate.longitude,
            endLatitude:    dropoff.coordinate.latitude,
            endLongitude:   dropoff.coordinate.longitude
        ) else { return [] }

        do {
            let response: UberPriceEstimatesResponse = try await APIClient.shared.get(
                url: url, headers: Endpoints.Uber.headers
            )
            return response.prices.map { price in
                RideOption(
                    id: price.productId,
                    provider: .uber,
                    productName: price.displayName,
                    priceRange: price.estimate,
                    estimatedMinutes: price.estimatedPickupMinutes,
                    isSurging: price.isSurging
                )
            }
        } catch {
            // Uber estimates failing should not block Lyft from showing
            return []
        }
    }

    // MARK: - Lyft Estimates

    private func fetchLyftEstimates(from pickup: CLLocation, to dropoff: CLLocation) async -> [RideOption] {
        guard let token = await validLyftToken() else { return [] }

        guard let url = Endpoints.Lyft.costEstimatesURL(
            startLatitude:  pickup.coordinate.latitude,
            startLongitude: pickup.coordinate.longitude,
            endLatitude:    dropoff.coordinate.latitude,
            endLongitude:   dropoff.coordinate.longitude
        ) else { return [] }

        do {
            let response: LyftCostEstimatesResponse = try await APIClient.shared.get(
                url: url, headers: Endpoints.Lyft.bearerHeaders(token: token)
            )
            return response.costEstimates.map { cost in
                RideOption(
                    id: cost.rideType,
                    provider: .lyft,
                    productName: cost.displayName,
                    priceRange: cost.priceRange,
                    estimatedMinutes: cost.estimatedPickupMinutes,
                    isSurging: cost.isSurging
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Lyft Token

    private func validLyftToken() async -> String? {
        if let token = lyftToken, let expiry = lyftTokenExpiry, expiry > Date() {
            return token
        }
        return await fetchLyftToken()
    }

    private func fetchLyftToken() async -> String? {
        guard let url = Endpoints.Lyft.tokenURL else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials&scope=public".data(using: .utf8)

        // Basic auth with client ID and secret
        let credentials = "\(APIKeys.lyftClientID):\(APIKeys.lyftClientSecret)"
        if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tokenResponse = try? decoder.decode(LyftTokenResponse.self, from: data) else { return nil }

        lyftToken = tokenResponse.accessToken
        lyftTokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        return tokenResponse.accessToken
    }

    // MARK: - Geocoding

    private func geocode(address: String) async -> CLLocation? {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            guard let location = placemarks.first?.location else { return nil }
            return location
        } catch {
            return nil
        }
    }

    // MARK: - Deep Link Booking

    /// Opens the ride app for the chosen option, falling back to the App Store if not installed.
    func book(option: RideOption) {
        guard let deepLink = option.deepLinkURL(
            pickup: pickupLocation,
            dropoffAddress: dropoffAddress
        ) else { return }

        if UIApplication.shared.canOpenURL(deepLink) {
            UIApplication.shared.open(deepLink)
        } else if let appStoreURL = option.appStoreURL {
            UIApplication.shared.open(appStoreURL)
        }
    }
}
