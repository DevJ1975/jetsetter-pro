// File: Core/Services/LocationService.swift

import Foundation
import CoreLocation

// MARK: - Location Error

enum LocationError: LocalizedError {
    case denied
    case restricted
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Location access was denied. Please enable it in Settings > Privacy > Location Services."
        case .restricted:
            return "Location access is restricted on this device."
        case .unavailable:
            return "Your location could not be determined."
        case .timeout:
            return "Location request timed out. Please try again."
        }
    }
}

// MARK: - LocationService

/// Async wrapper around CLLocationManager for one-shot current location requests.
/// NOTE: Add NSLocationWhenInUseUsageDescription to Info.plist before using.
final class LocationService: NSObject, CLLocationManagerDelegate {

    static let shared = LocationService()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Authorization Check

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    // MARK: - Current Location

    /// Requests the user's current location. Prompts for permission if not yet granted.
    /// Returns a `CLLocation` or throws a typed `LocationError`.
    func requestCurrentLocation() async throws -> CLLocation {
        switch locationManager.authorizationStatus {
        case .denied:
            throw LocationError.denied
        case .restricted:
            throw LocationError.restricted
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        if clError?.code == .locationUnknown {
            // locationUnknown is transient — CLLocationManager will retry automatically
            return
        }
        locationContinuation?.resume(throwing: LocationError.unavailable)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // When permission is granted after the prompt, retry the location request
        if isAuthorized {
            locationManager.requestLocation()
        } else if manager.authorizationStatus == .denied {
            locationContinuation?.resume(throwing: LocationError.denied)
            locationContinuation = nil
        }
    }
}

// MARK: - CLLocation Display Helper

extension CLLocation {
    /// Returns a human-readable coordinate string (e.g. "37.7749, -122.4194")
    var coordinateString: String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}
