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
    @Published var bookedRide: BookedRide? = nil

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

    // MARK: - Booking

    /// In-app web target for provider booking (§7.7 — presented via `.inAppWeb`).
    @Published var externalWebURL: URL?

    /// Books the chosen ride option. In live builds this hands off to the Uber/
    /// Lyft app via a deep link (falling back to the App Store if it isn't
    /// installed). In demo builds it mints a `BookedRide` with realistic driver,
    /// plate, vehicle, and ETA values, surfaces a confirmation sheet, and persists
    /// a marker so other parts of the app (Home, IRIS) can detect a booked ride.
    func book(option: RideOption) {
        // Live: hand off to the provider app; demo: fall through to the local
        // fake confirmation below so the investor demo stays self-contained.
        if !MockDataService.isEnabled {
            // In-app booking only (§7.7) — present the provider's mobile site
            // inside JetSetter Pro rather than handing off to the ride app.
            externalWebURL = option.provider == .lyft
                ? URL(string: "https://ride.lyft.com")
                : URL(string: "https://m.uber.com")
            return
        }

        let drivers = ["Marcus", "Aisha", "Diego", "Priya"]
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let plateLetters = String((0..<3).compactMap { _ in letters.randomElement() })
        let plateDigits = String(format: "%04d", Int.random(in: 0...9999))
        let plate = "\(plateLetters)-\(plateDigits)"

        let vehicle: String
        switch option.provider {
        case .uber:
            if option.productName.lowercased().contains("comfort") {
                vehicle = "Black Toyota Camry"
            } else if option.productName.lowercased().contains("xl") {
                vehicle = "Black SUV — Chevrolet Suburban"
            } else if option.productName.lowercased().contains("black") {
                vehicle = "Black Tesla Model S"
            } else {
                vehicle = "Silver Toyota RAV4"
            }
        case .lyft:
            if option.productName.lowercased().contains("xl") {
                vehicle = "Lyft Lux SUV — Cadillac Escalade"
            } else if option.productName.lowercased().contains("black") {
                vehicle = "Lyft Black — Mercedes E-Class"
            } else {
                vehicle = "White Honda Accord"
            }
        }

        let ride = BookedRide(
            provider: option.provider,
            productName: option.productName,
            driverName: drivers.randomElement() ?? "Marcus",
            licensePlate: plate,
            vehicle: vehicle,
            arrivalMinutes: Int.random(in: 3...7)
        )

        bookedRide = ride
        persistBookingMarker(for: ride)
    }

    /// Clears the active booking and removes the persisted marker.
    func cancelBookedRide() {
        bookedRide = nil
        UserDefaults.standard.removeObject(forKey: "uber_booked")
    }

    private func persistBookingMarker(for ride: BookedRide) {
        let payload: [String: Any] = [
            "provider": ride.provider.rawValue,
            "product": ride.productName,
            "driver": ride.driverName,
            "plate": ride.licensePlate,
            "vehicle": ride.vehicle,
            "arrival_minutes": ride.arrivalMinutes,
            "timestamp": Date().timeIntervalSince1970
        ]
        UserDefaults.standard.set(payload, forKey: "uber_booked")
    }
}

// MARK: - BookedRide

/// A confirmed ride created when the user taps "Book". Carries everything the
/// confirmation sheet needs to render — driver, vehicle, plate, ETA.
struct BookedRide: Identifiable, Equatable {
    let id = UUID()
    let provider: RideProvider
    let productName: String
    let driverName: String
    let licensePlate: String
    let vehicle: String
    let arrivalMinutes: Int
}
