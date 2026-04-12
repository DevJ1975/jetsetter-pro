// File: Features/Home/HomeViewModel.swift

import Foundation
import Combine
import CoreLocation
import SwiftUI

// MARK: - HomeViewModel

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: Published State

    @Published var cityName: String = ""
    @Published var currentWeather: WeatherData? = nil
    @Published var cityPhotoURL: URL? = nil
    @Published var destinationWeather: WeatherData? = nil
    @Published var destinationTimeZone: TimeZone? = nil
    @Published var nextFlightItem: ItineraryItem? = nil
    @Published var nextFlightTrip: Trip? = nil
    @Published var destinationCityPhotoURL: URL? = nil
    @Published var isLoading: Bool = false

    private let locationProvider = LocationProvider()

    // Cached formatters — DateFormatter allocation is expensive; reuse per ViewModel instance
    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private lazy var dateLabelFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    // MARK: - Load

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        loadNextFlight()
        await loadLocationData()
    }

    // MARK: - Location + Photo + Weather

    private func loadLocationData() async {
        // ── Mock mode: bypass GPS entirely, use configured demo city ─────────
        if MockDataService.isEnabled {
            cityName    = MockDataService.mockHomeCity
            cityPhotoURL = await CityPhotoService.shared.photoURL(for: cityName)
            currentWeather = try? await WeatherService.shared.fetch(
                latitude:  MockDataService.mockHomeLat,
                longitude: MockDataService.mockHomeLon
            )
            await loadDestinationData()
            return
        }

        // ── Real device: use GPS ─────────────────────────────────────────────
        let location = try? await locationProvider.requestLocationIfPossible()

        if let loc = location,
           let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc),
           let place = placemarks.first {
            cityName = place.locality ?? place.administrativeArea ?? "Your City"
        } else {
            let airport = UserPreferences.shared.homeAirport
            cityName = airport.isEmpty ? "Your City" : airport
        }

        cityPhotoURL = await CityPhotoService.shared.photoURL(for: cityName)

        if let loc = location {
            currentWeather = try? await WeatherService.shared.fetch(
                latitude:  loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
        }

        await loadDestinationData()
    }

    private func loadDestinationData() async {
        guard nextFlightTrip != nil else { return }

        if MockDataService.isEnabled {
            // Hardcoded Tokyo — no geocoder needed, works reliably in simulator
            destinationTimeZone = TimeZone(identifier: "Asia/Tokyo")
            destinationWeather  = try? await WeatherService.shared.fetch(
                latitude:  35.6762,
                longitude: 139.6503
            )
            destinationCityPhotoURL = await CityPhotoService.shared.photoURL(for: "Tokyo")
            return
        }

        guard let trip = nextFlightTrip else { return }
        let destCity = trip.destination
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? trip.destination

        if let placemarks = try? await CLGeocoder().geocodeAddressString(trip.destination),
           let place = placemarks.first,
           let destLoc = place.location {
            destinationTimeZone = place.timeZone
            destinationWeather  = try? await WeatherService.shared.fetch(
                latitude:  destLoc.coordinate.latitude,
                longitude: destLoc.coordinate.longitude
            )
        }
        destinationCityPhotoURL = await CityPhotoService.shared.photoURL(for: destCity)
    }

    // MARK: - Next Flight (UserDefaults)

    private func loadNextFlight() {
        // Ensure mock data is seeded on first launch
        MockDataService.prePopulateIfNeeded()

        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let trips = try? decoder.decode([Trip].self, from: data) else { return }

        let now = Date()
        let upcoming = trips.flatMap { trip in
            trip.items
                .filter { $0.type == .flight && $0.startDate > now }
                .map { (trip: trip, item: $0) }
        }

        if let earliest = upcoming.min(by: { $0.item.startDate < $1.item.startDate }) {
            nextFlightItem = earliest.item
            nextFlightTrip = earliest.trip
        }
    }

    // MARK: - Computed Properties

    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<21: return "Good Evening"
        default:      return "Good Night"
        }
    }

    var displayName: String {
        let name = UserPreferences.shared.displayName
        guard !name.isEmpty else { return "" }
        let first = name.components(separatedBy: " ").first ?? name
        return ", \(first)"
    }

    /// Flight number extracted from the title, e.g. "AA169" from "Flight — AA169 JFK → NRT"
    var parsedFlightNumber: String {
        guard let title = nextFlightItem?.title,
              let range = title.range(of: "[A-Z]{2,3}\\d{1,4}", options: .regularExpression)
        else { return "Flight" }
        return String(title[range])
    }

    /// Short airline name mapped from the 2–3 letter IATA code prefix
    var parsedAirlineName: String {
        guard let codeRange = parsedFlightNumber.range(of: "^[A-Z]{2,3}", options: .regularExpression) else {
            return "Airline"
        }
        let code = String(parsedFlightNumber[codeRange])
        return airlineNames[code] ?? "\(code) Airlines"
    }

    /// Gate extracted from the notes string, e.g. "B22" from "Gate B22 · Seat 3A"
    var parsedGate: String {
        guard let notes = nextFlightItem?.notes,
              let range = notes.range(of: "Gate ([A-Z0-9]+)", options: .regularExpression)
        else { return "—" }
        return String(notes[range]).replacingOccurrences(of: "Gate ", with: "")
    }

    /// Human-readable countdown, e.g. "3d 4h" or "45m"
    var timeUntilFlight: String {
        guard let date = nextFlightItem?.startDate, date > Date() else {
            return nextFlightItem != nil ? "Boarding" : "No flights"
        }
        let c = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: date)
        let d = c.day ?? 0; let h = c.hour ?? 0; let m = c.minute ?? 0
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var flightDepartureTime: String {
        guard let date = nextFlightItem?.startDate else { return "—" }
        return timeFormatter.string(from: date)
    }

    var flightDepartureDate: String {
        guard let date = nextFlightItem?.startDate else { return "" }
        return dateLabelFormatter.string(from: date)
    }

    var destinationLocalTimeString: String {
        guard let tz = destinationTimeZone else { return "" }
        // Timezone changes are infrequent; set once per destination load, not on every render
        timeFormatter.timeZone = tz
        let result = timeFormatter.string(from: Date())
        timeFormatter.timeZone = nil  // reset to system timezone for subsequent calls
        return result
    }

    // MARK: - Airline Lookup

    private let airlineNames: [String: String] = [
        "AA": "American",  "UA": "United",    "DL": "Delta",
        "WN": "Southwest", "AS": "Alaska",    "B6": "JetBlue",
        "NK": "Spirit",    "F9": "Frontier",  "G4": "Allegiant",
        "HA": "Hawaiian",  "BA": "British",   "LH": "Lufthansa",
        "AF": "Air France","EK": "Emirates",  "QR": "Qatar",
        "SQ": "Singapore", "CX": "Cathay",    "JL": "Japan Air",
        "NH": "ANA",       "KE": "Korean Air","AC": "Air Canada",
        "QF": "Qantas",    "TK": "Turkish",   "EY": "Etihad"
    ]
}

// MARK: - LocationProvider

/// Wraps CLLocationManager with a modern async/await interface.
/// Must be instantiated on the main thread (guaranteed when created inside a @MainActor type).
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocationIfPossible() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .notDetermined:
            let status = await withCheckedContinuation { (cont: CheckedContinuation<CLAuthorizationStatus, Never>) in
                authContinuation = cont
                manager.requestWhenInUseAuthorization()
            }
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                throw CLError(.denied)
            }
            return try await fetchLocation()
        case .authorizedWhenInUse, .authorizedAlways:
            return try await fetchLocation()
        default:
            throw CLError(.denied)
        }
    }

    private func fetchLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { cont in
            locationContinuation = cont
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationContinuation?.resume(returning: locations[0])
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined, let cont = authContinuation else { return }
        cont.resume(returning: status)
        authContinuation = nil
    }
}
