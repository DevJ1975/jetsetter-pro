// File: Features/GroundTransport/GroundTransportViewModel.swift

import Foundation
import CoreLocation
import MapKit

// MARK: - GroundTransportViewModel

/// Detects the pickup location, geocodes the destination, computes a real
/// driving time with MapKit, and builds pre-filled Uber / Lyft ride links.
@MainActor
@Observable
final class GroundTransportViewModel {

    // MARK: - Published State

    var pickupLocation: CLLocation? = nil
    var pickupAddress: String = "Detecting location…"
    var dropoffAddress: String = ""
    var rideOptions: [RideOption] = []
    var isLocating: Bool = false
    var isLoadingRoute: Bool = false
    var errorMessage: String? = nil
    var hasSearched: Bool = false

    /// Resolved destination for the current search (for the summary line).
    private(set) var resolvedDropoff: CLLocation? = nil

    // MARK: - Init

    init() {
        Task { await detectCurrentLocation() }
    }

    // MARK: - Location Detection

    /// Uses LocationService to get the device's current coordinates as the pickup point.
    func detectCurrentLocation() async {
        guard !isLocating else { return }
        isLocating = true
        errorMessage = nil
        pickupAddress = "Detecting location…"

        defer { isLocating = false }

        do {
            let location = try await LocationService.shared.requestCurrentLocation()
            pickupLocation = location
            pickupAddress = await reverseGeocode(location: location)
        } catch let error as LocationError {
            pickupAddress = "Location unavailable"
            errorMessage = error.errorDescription
        } catch {
            pickupAddress = "Location unavailable"
        }
    }

    private func reverseGeocode(location: CLLocation) async -> String {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let components = [placemark.name, placemark.locality, placemark.administrativeArea].compactMap { $0 }
                return components.joined(separator: ", ")
            }
        } catch {
            // Fall back to coordinate string on geocoding failure
        }
        return location.coordinateString
    }

    // MARK: - Route

    /// Geocodes the destination and computes the driving ETA, then builds one
    /// pre-filled ride link per provider.
    func findRides() async {
        guard !isLoadingRoute else { return }
        let dropoff = dropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dropoff.isEmpty else {
            errorMessage = "Please enter a dropoff destination."
            return
        }
        if pickupLocation == nil {
            await detectCurrentLocation()
        }
        guard let pickup = pickupLocation else {
            errorMessage = "Pickup location is not available yet. Please wait or tap the location button."
            return
        }

        isLoadingRoute = true
        errorMessage = nil
        rideOptions = []
        hasSearched = false
        defer {
            isLoadingRoute = false
            hasSearched = true
        }

        guard let destination = await geocode(address: dropoff) else {
            errorMessage = "Could not find \"\(dropoff)\". Please try a more specific address."
            return
        }
        resolvedDropoff = destination

        let (minutes, meters) = await drivingEstimate(from: pickup, to: destination)
        rideOptions = RideProvider.allCases.map { provider in
            RideOption(
                provider: provider,
                estimatedMinutes: minutes,
                distanceMeters: meters,
                rideURL: provider.rideURL(pickup: pickup, dropoff: destination, dropoffAddress: dropoff)
            )
        }
    }

    /// Driving time and distance from MapKit. Falls back to straight-line
    /// distance at 40 km/h if directions are unavailable (offline, unsupported region).
    private func drivingEstimate(from pickup: CLLocation, to destination: CLLocation) async -> (minutes: Int, meters: Double) {
        if let eta = await DepartureOptimizerService.shared.driveEstimate(from: pickup.coordinate, to: destination.coordinate) {
            return (max(1, Int(eta.travelTime / 60)), eta.distance)
        }
        let straight = pickup.distance(from: destination)
        return (max(1, Int(straight / 1000 / 40 * 60)), straight)
    }

    // MARK: - Geocoding

    private func geocode(address: String) async -> CLLocation? {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            return placemarks.first?.location
        } catch {
            return nil
        }
    }

    // MARK: - Booking

    /// In-app web target for the provider's ride flow (§7.7 — presented via `.inAppWeb`).
    var externalWebURL: URL?

    /// Opens the provider's ride flow with the route pre-filled. Persists a
    /// timestamped marker so Home can rest the "pre-book your ride" nudge for
    /// the next 12 hours (long enough to cover this departure, not the next trip).
    func open(option: RideOption) {
        externalWebURL = option.rideURL
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.rideOpenedAtKey)
        UserDefaults.standard.set([
            "provider": option.provider.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ], forKey: Self.bookedDetailsKey)
    }

    /// Marker keys shared with ProactiveSuggestions' ride-suppression logic.
    static let rideOpenedAtKey = "ride_opened_at"
    fileprivate static let bookedDetailsKey = "uber_booked_details"

    /// True when the traveler opened a ride app within the last 12 hours.
    static var recentlyOpenedRide: Bool {
        let opened = UserDefaults.standard.double(forKey: rideOpenedAtKey)
        return opened > 0 && Date().timeIntervalSince1970 - opened < 12 * 3_600
    }
}
