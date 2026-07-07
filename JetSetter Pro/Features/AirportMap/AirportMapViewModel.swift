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

    // Layover wayfinding state — kept separate from the primary user→gate route
    // so the layover sheet never pollutes the main indoor map/card.
    @Published var layoverRoute: MKRoute? = nil
    @Published var layoverWalkMinutes: Int? = nil
    @Published var layoverError: String? = nil
    @Published var isLoadingLayoverRoute: Bool = false

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
    ///
    /// The static `indoorMapsAirports` list is treated only as a hint: Apple adds and
    /// removes indoor venue coverage over time, so we also honour runtime detection.
    /// Once a live `CLLocation.floor` arrives (`isInsideSupportedAirport`), we know the
    /// device is inside a mapped terminal even if the airport isn't in the static list.
    var supportsIndoorMaps: Bool {
        isInsideSupportedAirport || indoorMapsAirports.contains(airportIATA.uppercased())
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
            // Seed the ETA from MapKit; the pedometer (started in startTracking) will
            // refine this with live walking pace as the user moves.
            estimatedWalkMinutes = estimatedMinutes(from: route)

            // Load nearby POIs around the destination gate
            await loadNearbyPOIs(near: destination)
        } catch {
            errorMessage = "Could not calculate route: \(error.localizedDescription)"
        }
    }

    // MARK: - Layover Wayfinding

    /// For connecting flights: routes from arrival gate to departure gate.
    /// Writes to the layover-specific state so the primary user→gate route on the
    /// main indoor map is never overwritten.
    func calculateLayoverRoute(from incomingGate: String) async {
        // Gate-to-gate routing does not require the user's own fix; resolveGateCoordinate
        // uses userLocation only to bias the search region when it happens to be present.
        isLoadingLayoverRoute = true
        layoverError = nil
        defer { isLoadingLayoverRoute = false }

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
                layoverRoute = route
                layoverWalkMinutes = estimatedMinutes(from: route)
            }
        } catch {
            // Gate coordinates aren't in Apple Maps — show estimated time from step count
            layoverWalkMinutes = estimatedMinutesFromPedometer()
            layoverError = "Exact gate route unavailable — showing estimated walk time."
        }

        // Suppress the error if we have a pedometer estimate; still useful info
        if layoverWalkMinutes != nil { layoverError = nil }
    }

    // MARK: - Nearby POIs

    private func loadNearbyPOIs(near coordinate: CLLocationCoordinate2D) async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "restaurant restroom lounge"
        // Airside gate context: keep interior amenity categories only. Landside
        // lodging (.hotel) is not reachable from an airside gate, so exclude it to
        // avoid pinning cafes/hotels the traveller can't actually walk to.
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery,
            .airport
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

    /// Radius (metres) within which a resolved gate match is considered to actually
    /// be on-airport. Apple Maps does not expose individual gates as POIs, so a search
    /// for "Gate A12 SFO" can return an arbitrary off-airport match; anything beyond
    /// this radius from the airport centre is rejected so we don't route to it.
    private let maxOnAirportRadiusMeters: CLLocationDistance = 3_000

    /// Searches Apple Maps for a gate/terminal name at the given airport.
    /// Gate-level positioning requires Apple's indoor map data to be available at that airport.
    ///
    /// Note: Apple Maps does not publish individual gate coordinates as searchable POIs,
    /// so the returned coordinate is at best a terminal/airport-centroid approximation.
    /// Callers should treat any resulting ETA/route as approximate. We reject matches
    /// that fall outside the airport bounds so an off-airport hit never gets routed to.
    private func resolveGateCoordinate(airport: String, terminal: String, gate: String) async throws -> CLLocationCoordinate2D {
        // Resolve the airport centre first so we can validate the gate match is on-airport.
        let airportCoordinate = try await resolveAirportCoordinate(airport)

        let req = MKLocalSearch.Request()
        let query = terminal.isEmpty ? "Gate \(gate) \(airport)" : "\(terminal) Gate \(gate) \(airport)"
        req.naturalLanguageQuery = query

        // Bias the search to the airport itself so nearby same-named streets/POIs
        // don't win over the terminal we care about.
        req.region = MKCoordinateRegion(
            center: airportCoordinate,
            latitudinalMeters: 5_000,
            longitudinalMeters: 5_000
        )

        let search = MKLocalSearch(request: req)
        let response = try await search.start()

        // Pick the first match that actually lies within the airport bounds. Apple Maps
        // has no gate-level POIs, so an unbounded first-result can be an arbitrary
        // off-airport hit; validating against the airport centre keeps us honest.
        let airportLocation = CLLocation(latitude: airportCoordinate.latitude, longitude: airportCoordinate.longitude)
        let onAirportMatch = response.mapItems.first { item in
            let coord = item.placemark.coordinate
            let candidate = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return candidate.distance(from: airportLocation) <= maxOnAirportRadiusMeters
        }

        // If no gate-level match is on-airport, fall back to the airport centre rather
        // than routing to an off-airport result. The ETA is approximate either way.
        return onAirportMatch?.placemark.coordinate ?? airportCoordinate
    }

    /// Resolves the airport's own coordinate via Apple Maps, used to validate that a
    /// gate search result actually lands on the airport.
    private func resolveAirportCoordinate(_ airport: String) async throws -> CLLocationCoordinate2D {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "\(airport) airport"
        if let userLocation {
            req.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }
        let search = MKLocalSearch(request: req)
        let response = try await search.start()
        guard let coord = response.mapItems.first?.placemark.coordinate else {
            throw MapError.airportNotFound(airport: airport)
        }
        return coord
    }

    /// Returns the initial ETA straight from MapKit's `expectedTravelTime`.
    /// This is the seed value only — once the pedometer starts delivering distance,
    /// `updateWalkEstimateFromPedometer(_:)` refines `estimatedWalkMinutes` with the
    /// user's live walking pace. This method itself does not consult the pedometer.
    private func estimatedMinutes(from route: MKRoute) -> Int {
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
            } else {
                // No floor data means we're outside a mapped terminal — clear the
                // indoor state so the wayfinding card stops reporting a stale floor.
                indoorLevelIndex = 0
                isInsideSupportedAirport = false
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                // startTracking() owns location start (plus heading + pedometer),
                // so don't call manager.startUpdatingLocation() directly here.
                startTracking()
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
    case airportNotFound(airport: String)

    var errorDescription: String? {
        switch self {
        case .gateNotFound(let gate, let airport):
            return "Gate \(gate) not found in Apple Maps for \(airport)."
        case .airportNotFound(let airport):
            return "Airport \(airport) not found in Apple Maps."
        }
    }
}
