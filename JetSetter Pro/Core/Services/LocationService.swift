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
        let status = locationManager.authorizationStatus
        switch status {
        case .denied:
            throw LocationError.denied
        case .restricted:
            throw LocationError.restricted
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Never clobber an in-flight request — overwriting the stored
            // continuation would leak the previous one (permanent hang). Reject
            // the new caller instead so each continuation resumes exactly once.
            guard self.locationContinuation == nil else {
                continuation.resume(throwing: LocationError.unavailable)
                return
            }
            self.locationContinuation = continuation

            if status == .notDetermined {
                // Wait for the authorization callback before requesting a fix —
                // calling requestLocation() before the prompt is answered fails
                // immediately. locationManagerDidChangeAuthorization drives it.
                self.locationManager.requestWhenInUseAuthorization()
            } else {
                self.locationManager.requestLocation()
            }
        }
    }

    /// Resumes the pending continuation exactly once, then clears it.
    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(with: result)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        if clError?.code == .locationUnknown {
            // locationUnknown is transient — CLLocationManager will retry automatically
            return
        }
        finish(with: .failure(LocationError.unavailable))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Only act on the authorization change if a request is actually waiting.
        guard locationContinuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(LocationError.denied))
        default:
            break   // still .notDetermined — keep waiting
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
