// File: Features/GroundTransport/GroundTransportViewModel.swift

import Foundation
import CoreLocation
import UIKit

// MARK: - GroundTransportViewModel

/// Manages location detection, ride estimate fetching from Uber,
/// and deep-link dispatch to the ride apps.
@MainActor
@Observable
final class GroundTransportViewModel {

    // MARK: - Published State

    var pickupLocation: CLLocation? = nil
    var pickupAddress: String = "Detecting location…"
    var dropoffAddress: String = ""
    var rideOptions: [RideOption] = []
    var isLocating: Bool = false
    var isLoadingEstimates: Bool = false
    var errorMessage: String? = nil
    var hasSearched: Bool = false
    var bookedRide: BookedRide? = nil

    // MARK: - Provider Reachability

    /// Tracks whether each provider fetch errored (auth/network) versus genuinely
    /// returned zero options, so an empty result can distinguish "we couldn't reach
    /// Uber" from "no rides for this route." Lyft never sets a failure flag — its
    /// public estimate API is discontinued, not merely unreachable.
    private var uberFailed: Bool = false
    private var lyftFailed: Bool = false

    // MARK: - Cross-Provider Comparison

    /// ID of the cheapest option across both providers (lowest parsed price bound),
    /// or `nil` if none can be compared. Drives the "Best price" badge.
    var cheapestOptionID: String? {
        rideOptions
            .filter { $0.lowestPriceValue < .greatestFiniteMagnitude }
            .min { $0.lowestPriceValue < $1.lowestPriceValue }?.id
    }

    /// ID of the fastest option across both providers (shortest trip estimate),
    /// or `nil` if there are none. Drives the "Fastest" badge.
    var fastestOptionID: String? {
        rideOptions.min { $0.estimatedMinutes < $1.estimatedMinutes }?.id
    }

    // MARK: - Cached Uber Token
    // Uber's client-credentials tokens are valid for ~30 days; cache and reuse
    // rather than minting one per request (the grant is rate-limited to 100/hr,
    // and each new token invalidates the oldest).

    private var uberToken: String? = nil
    private var uberTokenExpiry: Date? = nil

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

    /// Fetches ride estimates for the current route. Uber is queried live; Lyft's
    /// public estimate API is discontinued, so only Uber options are returned.
    func fetchEstimates() async {
        guard !isLoadingEstimates else { return }  // Prevent concurrent estimate fetches
        let dropoff = dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dropoff.isEmpty else {
            errorMessage = "Please enter a dropoff destination."
            return
        }
        // If the pickup hasn't resolved yet, transparently retry detection once
        // before giving up — so a user who searches before location resolves
        // doesn't have to discover the refresh button.
        if pickupLocation == nil {
            await detectCurrentLocation()
        }
        guard let pickup = pickupLocation else {
            errorMessage = "Pickup location is not available yet. Please wait or tap the location button."
            return
        }

        isLoadingEstimates = true
        errorMessage = nil
        rideOptions = []
        hasSearched = false
        uberFailed = false
        lyftFailed = false

        defer {
            isLoadingEstimates = false
            hasSearched = true
        }

        // Geocode the dropoff address to get coordinates
        guard let dropoffLocation = await geocode(address: dropoff) else {
            errorMessage = "Could not find \"\(dropoff)\". Please try a more specific address."
            return
        }

        // Fetch from both providers concurrently (Lyft short-circuits to []).
        async let uberOptions = fetchUberEstimates(from: pickup, to: dropoffLocation)
        async let lyftOptions = fetchLyftEstimates(from: pickup, to: dropoffLocation)

        let (uber, lyft) = await (uberOptions, lyftOptions)
        rideOptions = uber + lyft

        if rideOptions.isEmpty {
            // Distinguish a genuine "no rides for this route" from a provider we
            // couldn't reach (auth/network), so users don't waste time editing a
            // perfectly valid destination. Lyft cannot be "unreachable" — its API
            // is gone — so only Uber drives the reachability messaging.
            if uberFailed {
                errorMessage = "We couldn't reach Uber right now. Please try again shortly."
            } else {
                errorMessage = "No rides available for this route. Try a different destination."
            }
        }
    }

    // MARK: - Uber Estimates

    private func fetchUberEstimates(from pickup: CLLocation, to dropoff: CLLocation) async -> [RideOption] {
        // A missing/invalid token is an auth failure, not "no rides" — flag it.
        guard let token = await validUberToken() else {
            uberFailed = true
            return []
        }

        guard let url = Endpoints.Uber.priceEstimatesURL(
            startLatitude:  pickup.coordinate.latitude,
            startLongitude: pickup.coordinate.longitude,
            endLatitude:    dropoff.coordinate.latitude,
            endLongitude:   dropoff.coordinate.longitude
        ) else { return [] }

        do {
            let response: UberPriceEstimatesResponse = try await APIClient.shared.get(
                url: url, headers: Endpoints.Uber.headers(token: token)
            )
            return response.prices.map { price in
                RideOption(
                    id: price.productId,
                    provider: .uber,
                    productName: price.displayName,
                    priceRange: price.estimate,
                    estimatedMinutes: price.estimatedTripMinutes,
                    isSurging: price.isSurging
                )
            }
        } catch {
            // Uber estimates failing should not block other options from showing,
            // but record the failure so a fully-empty result reports it accurately.
            uberFailed = true
            return []
        }
    }

    // MARK: - Lyft Estimates (discontinued)

    private func fetchLyftEstimates(from pickup: CLLocation, to dropoff: CLLocation) async -> [RideOption] {
        // Lyft discontinued its public consumer ride-estimate API and SDKs, so
        // there is no live endpoint to call. We return no Lyft estimates and do
        // NOT flag a reachability failure (the API being gone is not a transient
        // error the user can retry around). Booking still deep-links to
        // ride.lyft.com in `book(option:)` for users who prefer Lyft.
        return []
    }

    // MARK: - Uber Token

    private func validUberToken() async -> String? {
        if let token = uberToken, let expiry = uberTokenExpiry, expiry > Date() {
            return token
        }
        return await fetchUberToken()
    }

    /// Mints an app-level Uber access token via the OAuth2 client-credentials
    /// grant (scope `ride_request.estimate`).
    private func fetchUberToken() async -> String? {
        guard let url = Endpoints.Uber.tokenURL else { return nil }
        let clientID = APIKeys.uberClientID
        let clientSecret = APIKeys.uberClientSecret
        guard !clientID.isEmpty, !clientSecret.isEmpty else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "scope", value: Endpoints.Uber.estimateScope)
        ]
        request.httpBody = (components.percentEncodedQuery ?? "").data(using: .utf8)

        // Routed through the shared APIClient for the same typed-error + status
        // handling as the estimate GET; a non-2xx or transport failure surfaces
        // as a thrown APIError, which we treat as "no token available."
        guard let data = try? await APIClient.shared.data(for: request) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tokenResponse = try? decoder.decode(UberTokenResponse.self, from: data) else { return nil }

        uberToken = tokenResponse.accessToken
        // Refresh a minute early so an in-flight request never races expiry.
        uberTokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn) - 60)
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
    var externalWebURL: URL?

    /// Books the chosen ride option. In live builds this hands off to the Uber/
    /// Lyft app via a deep link (falling back to the App Store if it isn't
    /// installed). In demo builds it mints a `BookedRide` with realistic driver,
    /// plate, vehicle, and ETA values, surfaces a confirmation sheet, and persists
    /// a marker so other parts of the app (Home, IRIS) can detect a booked ride.
    func book(option: RideOption) {
        // In-app booking only (§7.7) — present the provider's mobile site inside
        // JetSetter Pro rather than handing off to the ride app. Persist a
        // lightweight marker so Home/IRIS ride suppression fires.
        externalWebURL = option.provider == .lyft
            ? URL(string: "https://ride.lyft.com")
            : URL(string: "https://m.uber.com")
        persistBookingMarker(provider: option.provider, details: [
            "provider": option.provider.rawValue,
            "product": option.productName,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    /// Clears the active booking and removes the persisted marker.
    func cancelBookedRide() {
        bookedRide = nil
        UserDefaults.standard.removeObject(forKey: Self.bookedMarkerKey)
        UserDefaults.standard.removeObject(forKey: Self.bookedDetailsKey)
    }

    // Marker keys shared with IRISTriggers ride-suppression logic.
    fileprivate static let bookedMarkerKey = "uber_booked"
    fileprivate static let bookedDetailsKey = "uber_booked_details"

    /// Persists the "a ride is booked" marker so Home/IRIS can suppress the
    /// book-a-ride suggestion. Writes a Bool sentinel at `uber_booked` (what
    /// IRISTriggers reads via `bool(forKey:)`) and the richer payload under a
    /// separate `uber_booked_details` key.
    private func persistBookingMarker(provider: RideProvider, details: [String: Any]) {
        UserDefaults.standard.set(true, forKey: Self.bookedMarkerKey)
        UserDefaults.standard.set(details, forKey: Self.bookedDetailsKey)
    }
}

// MARK: - Uber Token Response

/// Decodes the OAuth2 client-credentials token response from Uber.
private struct UberTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
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
    /// The fare range from the booked option (e.g. "$12–$18") — the single most
    /// important detail at booking time, surfaced on the confirmation sheet.
    let priceRange: String
    /// Whether the booked option was surging, so the sheet can flag it.
    let isSurging: Bool
}
