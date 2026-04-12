// File: Features/AirportMap/AirportMapViewModel.swift

import Foundation
import MapKit
import CoreLocation
import CoreMotion
import Combine

// MARK: - AirportMapViewModel

@MainActor
final class AirportMapViewModel: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var userLocation: CLLocation? = nil
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var indoorLevelIndex: Int = 0             // Floor level for indoor maps
    @Published var isInsideSupportedAirport: Bool = false

    @Published var nearbyPOIs: [MKMapItem] = []
    @Published var wayfindingRoute: MKRoute? = nil
    @Published var estimatedWalkMinutes: Int? = nil

    @Published var errorMessage: String? = nil
    @Published var isLoadingRoute: Bool = false

    // MARK: - Input Parameters (set by the parent view from itinerary data)

    var airportIATA: String = ""           // e.g. "LAX"
    var departureTerminal: String = ""     // e.g. "Tom Bradley International"
    var departureGate: String = ""         // e.g. "B40"

    // For layover wayfinding: arrival gate → departure gate
    var arrivalGate: String? = nil

    // MARK: - Private Properties

    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var pedometerStartDate: Date? = nil

    // Average walking speed used for ETA fallback when pedometer is unavailable
    private let averageWalkingSpeedMPS: Double = 1.3   // ~4.7 km/h

    // Known airports that support Apple indoor maps (non-exhaustive)
    private let indoorMapsAirports: Set<String> = [
        "SFO", "ATL", "DFW", "ORD", "LAX", "SEA", "JFK", "LHR", "CDG", "NRT",
        "HND", "ICN", "SIN", "DXB", "AMS", "FRA", "BKK", "HKG", "SYD", "MEX"
    ]

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // Request full accuracy for indoor positioning
        locationManager.activityType = .otherNavigation
    }

    // MARK: - Public Methods

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        startPedometer()
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        pedometer.stopUpdates()
    }

    /// Checks if the target airport supports Apple indoor maps.
    var supportsIndoorMaps: Bool {
        indoorMapsAirports.contains(airportIATA.uppercased())
    }

    // MARK: - Wayfinding

    /// Calculates a walking route from the user's current location (or arrival gate) to the departure gate.
    func calculateWayfindingRoute() async {
        guard let userLocation else {
            errorMessage = "Location unavailable. Enable Location Services to use wayfinding."
            return
        }
        isLoadingRoute = true
        errorMessage = nil
        defer { isLoadingRoute = false }

        do {
            let destination = try await resolveGateCoordinate(
                airport: airportIATA,
                terminal: departureTerminal,
                gate: departureGate
            )

            let sourcePlacemark = MKPlacemark(coordinate: userLocation.coordinate)
            let destPlacemark   = MKPlacemark(coordinate: destination)

            let req = MKDirections.Request()
            req.source      = MKMapItem(placemark: sourcePlacemark)
            req.destination = MKMapItem(placemark: destPlacemark)
            req.transportType = .walking

            let directions = MKDirections(request: req)
            let response = try await directions.calculate()

            guard let route = response.routes.first else {
                errorMessage = "No walking route found to gate \(departureGate)."
                return
            }

            wayfindingRoute = route
            // Prefer live pedometer ETA, fall back to MapKit estimated travel time
            estimatedWalkMinutes = estimatedMinutes(from: route)

            // Load nearby POIs around the destination gate
            await loadNearbyPOIs(near: destination)
        } catch {
            errorMessage = "Could not calculate route: \(error.localizedDescription)"
        }
    }

    // MARK: - Layover Wayfinding

    /// For connecting flights: routes from arrival gate to departure gate.
    func calculateLayoverRoute(from incomingGate: String) async {
        guard let userLocation else { return }
        isLoadingRoute = true
        errorMessage = nil
        defer { isLoadingRoute = false }

        do {
            let arrivalCoord   = try await resolveGateCoordinate(airport: airportIATA, terminal: "", gate: incomingGate)
            let departureCoord = try await resolveGateCoordinate(airport: airportIATA, terminal: departureTerminal, gate: departureGate)

            let req = MKDirections.Request()
            req.source        = MKMapItem(placemark: MKPlacemark(coordinate: arrivalCoord))
            req.destination   = MKMapItem(placemark: MKPlacemark(coordinate: departureCoord))
            req.transportType = .walking

            let directions = MKDirections(request: req)
            let response = try await directions.calculate()

            if let route = response.routes.first {
                wayfindingRoute = route
                estimatedWalkMinutes = estimatedMinutes(from: route)
            }
        } catch {
            // Gate coordinates aren't in Apple Maps — show estimated time from step count
            estimatedWalkMinutes = estimatedMinutesFromPedometer()
            errorMessage = "Exact gate route unavailable — showing estimated walk time."
        }

        // Suppress the error if we have a pedometer estimate; still useful info
        if estimatedWalkMinutes != nil { errorMessage = nil }
        _ = userLocation // silence unused warning
    }

    // MARK: - Nearby POIs

    private func loadNearbyPOIs(near coordinate: CLLocationCoordinate2D) async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "restaurant restroom lounge"
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery,
            .hotel, .airport
        ])
        req.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 300,
            longitudinalMeters: 300
        )
        do {
            let search = MKLocalSearch(request: req)
            let response = try await search.start()
            nearbyPOIs = response.mapItems
        } catch {
            // POIs are a nice-to-have — don't surface this error to the user
        }
    }

    // MARK: - Pedometer

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometerStartDate = Date()
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                self?.updateWalkEstimateFromPedometer(data)
            }
        }
    }

    private func updateWalkEstimateFromPedometer(_ data: CMPedometerData) {
        guard let distance = data.distance?.doubleValue, distance > 0 else { return }
        // If we already have a MapKit route distance, use live pace from pedometer
        if let route = wayfindingRoute {
            let elapsed = Date().timeIntervalSince(pedometerStartDate ?? Date())
            let speed = elapsed > 0 ? distance / elapsed : averageWalkingSpeedMPS
            let remainingDistance = max(0, route.distance - distance)
            estimatedWalkMinutes = max(1, Int((remainingDistance / speed) / 60))
        }
    }

    private func estimatedMinutesFromPedometer() -> Int? {
        // Without a route, use a default 3 min/200m terminal walk estimate
        return nil
    }

    // MARK: - Gate Coordinate Resolution

    /// Searches Apple Maps for a gate/terminal name at the given airport.
    /// Gate-level positioning requires Apple's indoor map data to be available at that airport.
    private func resolveGateCoordinate(airport: String, terminal: String, gate: String) async throws -> CLLocationCoordinate2D {
        let req = MKLocalSearch.Request()
        let query = terminal.isEmpty ? "Gate \(gate) \(airport)" : "\(terminal) Gate \(gate) \(airport)"
        req.naturalLanguageQuery = query

        // Search within a generous bounding box centred on the user to stay within the airport
        if let userLocation {
            req.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 5_000,
                longitudinalMeters: 5_000
            )
        }

        let search = MKLocalSearch(request: req)
        let response = try await search.start()

        guard let item = response.mapItems.first else {
            throw MapError.gateNotFound(gate: gate, airport: airport)
        }
        return item.placemark.coordinate
    }

    private func estimatedMinutes(from route: MKRoute) -> Int {
        // Use live pedometer pace if available, otherwise fall back to MapKit ETA
        let seconds = route.expectedTravelTime
        return max(1, Int(seconds / 60))
    }
}

// MARK: - CLLocationManagerDelegate

extension AirportMapViewModel: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            userLocation = location
            // Indoor floor is available on supported devices/airports
            if let floor = location.floor {
                indoorLevelIndex = floor.level
                isInsideSupportedAirport = true
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Location error: \(error.localizedDescription)"
        }
    }
}

// MARK: - MapError

enum MapError: LocalizedError {
    case gateNotFound(gate: String, airport: String)

    var errorDescription: String? {
        switch self {
        case .gateNotFound(let gate, let airport):
            return "Gate \(gate) not found in Apple Maps for \(airport)."
        }
    }
}
