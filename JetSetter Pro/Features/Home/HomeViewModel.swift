// File: Features/Home/HomeViewModel.swift

import Foundation
import CoreLocation
import SwiftUI

// MARK: - HomeViewModel

@MainActor
@Observable
final class HomeViewModel {

    // MARK: Published State

    var cityName: String = ""
    var currentWeather: WeatherData? = nil
    var cityPhotoURL: URL? = nil
    var destinationWeather: WeatherData? = nil
    var destinationTimeZone: TimeZone? = nil {
        didSet { destinationTimeFormatter.timeZone = destinationTimeZone }
    }
    var nextFlightItem: ItineraryItem? = nil
    var nextFlightTrip: Trip? = nil
    var destinationCityPhotoURL: URL? = nil
    var isLoading: Bool = false

    /// The "leave for the airport" summary for the next flight, shown on Home
    /// when the flight is within the next 24 hours. Nil hides the card.
    var departureInfo: HomeDepartureInfo? = nil

    /// Compact, view-ready departure summary decoupled from the service model so
    /// the card can render either a live recommendation or the shared briefing.
    struct HomeDepartureInfo: Equatable {
        let leaveBy: String
        let detail: String        // e.g. "34 min drive · TSA 22 min"
        let weather: String?      // e.g. "Clear skies, 74°F"
        let urgencyLabel: String? // e.g. "On time" (live only)
    }

    /// All trips loaded from local storage — exposed for the Intelligence engine.
    private(set) var loadedTrips: [Trip] = []

    // MARK: IRIS Suggestion Queue
    //
    // The Home hero surfaces the single highest-priority IRIS suggestion plus
    // a "+N more" badge when other triggers are also active. The full queue is
    // exposed so screens that want to expand the stack can iterate it.
    private(set) var irisSuggestions: [IRISSuggestion] = []

    /// The top-priority suggestion to render in the IRIS hero card, if any.
    var topIRISSuggestion: IRISSuggestion? { irisSuggestions.first }

    /// Count of additional suggestions beyond the top one. Drives "+N more".
    var additionalIRISSuggestionCount: Int {
        max(0, irisSuggestions.count - 1)
    }

    private let locationProvider = LocationProvider()

    // Cached formatters — DateFormatter allocation is expensive; reuse per ViewModel instance
    @ObservationIgnored private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    @ObservationIgnored private lazy var dateLabelFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
    /// Dedicated formatter for destination-local time so the shared `timeFormatter`
    /// is never mutated at render time. Its timeZone tracks `destinationTimeZone`.
    @ObservationIgnored private lazy var destinationTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; f.timeZone = destinationTimeZone; return f
    }()

    // MARK: - Load

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        loadNextFlight()
        reloadIRISSuggestions()
        pushNextFlightToWatch()
        await loadLocationData()
        await loadDepartureRecommendation()
    }

    /// Computes the "leave for the airport" summary for the next flight when it's
    /// within the next 24 hours — surfacing DepartureOptimizerService on Home
    /// (previously reachable only from its own screen). Falls back to the shared
    /// DepartureBriefing when a live estimate isn't available (e.g. no location).
    func loadDepartureRecommendation() async {
        guard let item = nextFlightItem else { departureInfo = nil; return }
        let secondsUntil = item.startDate.timeIntervalSinceNow
        guard secondsUntil > 0, secondsUntil <= 24 * 3600 else { departureInfo = nil; return }

        let originIATA = (item.location ?? "")
            .components(separatedBy: " → ").first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        // Resolve a starting coordinate — demo city in mock mode, else live GPS.
        let coord: CLLocationCoordinate2D?
        if MockDataService.isEnabled {
            coord = CLLocationCoordinate2D(
                latitude: MockDataService.mockHomeLat,
                longitude: MockDataService.mockHomeLon
            )
        } else {
            coord = (try? await locationProvider.requestLocationIfPossible())?.coordinate
        }

        if let coord, !originIATA.isEmpty,
           let rec = await DepartureOptimizerService.shared.recommend(
                currentLocation: coord,
                airportIATA: originIATA,
                scheduledDeparture: item.startDate
           ) {
            departureInfo = HomeDepartureInfo(
                leaveBy: timeFormatter.string(from: rec.leaveAt),
                detail: "\(rec.driveMinutes) min drive · TSA \(rec.tsaWait.display)",
                weather: rec.weather.map { "\($0.conditionLabel), \($0.temperatureF)°F" },
                urgencyLabel: rec.urgency.label
            )
            return
        }

        // Fallback to the shared briefing so the card still appears meaningfully.
        // A live re-roll (`cachedLive`) reflects the user's real location/traffic, so
        // present it as-is. The persona default, however, is a canned estimate NOT
        // computed from the user's actual location — surfacing its concrete "leave by"
        // time unlabeled could lead a traveler to trust a number that isn't theirs, so
        // flag it as approximate ("Est.") so it doesn't read as a live calculation.
        if let live = DepartureBriefing.cachedLive {
            departureInfo = HomeDepartureInfo(
                leaveBy: live.leaveBy,
                detail: "\(live.driveMinutes) min drive · TSA \(live.tsaMinutes) min",
                weather: "\(live.weatherLabel), \(live.temperatureF)°F",
                urgencyLabel: nil
            )
        } else {
            let b = DepartureBriefing.personaDefault
            departureInfo = HomeDepartureInfo(
                leaveBy: b.leaveBy,
                detail: "Est. · \(b.driveMinutes) min drive · TSA \(b.tsaMinutes) min",
                weather: "\(b.weatherLabel), \(b.temperatureF)°F",
                urgencyLabel: "Estimate"
            )
        }
    }

    /// Re-evaluates IRIS triggers and refreshes the published queue.
    /// Safe to call after any state change that might shift trigger eligibility.
    func reloadIRISSuggestions() {
        irisSuggestions = IRISTriggers.shared.evaluateAll()
    }

    /// Pushes the current next-flight snapshot to a paired Apple Watch. Called
    /// after `loadNextFlight()`. Safe when no watch is paired.
    private func pushNextFlightToWatch() {
        guard let item = nextFlightItem else {
            WatchConnectivityService.shared.updateNextFlight(nil)
            return
        }
        let parts = (item.location ?? "").components(separatedBy: " → ")
        let snapshot = NextFlightSnapshot(
            flightNumber: parsedFlightNumber,
            airlineName: parsedAirlineName,
            originIATA: parts.first?.trimmingCharacters(in: .whitespaces) ?? "",
            destinationIATA: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "",
            gate: parsedGate == "—" ? nil : parsedGate,
            terminal: nil,
            departure: item.startDate,
            isCheckedIn: CheckInStateStore.isCheckedIn(
                flightNumber: parsedFlightNumber,
                departure: item.startDate
            )
        )
        WatchConnectivityService.shared.updateNextFlight(snapshot)
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
            // Reverse-geocode failed (no GPS / lookup error). Do NOT fall back to the
            // raw home-airport IATA code — an airport code (e.g. "JFK") is not a city
            // name, reads as broken under the location pin, and yields an irrelevant
            // photo when handed to CityPhotoService. Show a neutral placeholder and
            // skip the photo lookup entirely.
            cityName = "Your City"
        }

        // Only fetch a photo when we resolved a real place name. "Your City" is a
        // placeholder, not a query the photo service can meaningfully satisfy.
        if cityName != "Your City" {
            cityPhotoURL = await CityPhotoService.shared.photoURL(for: cityName)
        }

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

        // Clear prior destination's data so a failed geocode/photo lookup shows an
        // empty/loading state rather than stale values from the previous trip.
        destinationTimeZone = nil
        destinationWeather = nil
        destinationCityPhotoURL = nil

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

        guard let trips = CodableDefaults.load([Trip].self, forKey: "jetsetter_trips") else { return }

        loadedTrips = trips

        // Learning: record any newly-ended trips (once each) as completed/visited signals.
        recordCompletedTrips(trips)

        let now = Date()
        // Keep a flight "current" until it has actually landed (its endDate), so a
        // flight the user is currently on — departed but not yet arrived — stays on
        // Home instead of vanishing mid-journey and taking the tracker/check-in
        // context with it. When endDate is missing, fall back to a buffer past
        // startDate so the card still lingers through boarding/taxi rather than
        // disappearing the instant the scheduled departure passes.
        let inProgressBuffer: TimeInterval = 4 * 3600
        let upcoming = trips.flatMap { trip in
            trip.items
                .filter { item in
                    guard item.type == .flight else { return false }
                    let stillRelevantUntil = item.endDate ?? item.startDate.addingTimeInterval(inProgressBuffer)
                    return stillRelevantUntil > now
                }
                .map { (trip: trip, item: $0) }
        }

        if let earliest = upcoming.min(by: { $0.item.startDate < $1.item.startDate }) {
            nextFlightItem = earliest.item
            nextFlightTrip = earliest.trip
        }
    }

    /// Detects newly-ENDED trips and records them for the learning layer exactly once,
    /// deduping via a persisted id set. Trip has no stored booking date, so leadDays
    /// is omitted. Consent gating happens inside TravelProfileStore.record().
    private func recordCompletedTrips(_ trips: [Trip]) {
        let now = Date()
        let learnedKey = "jetsetter_learned_completed_trips"

        var learnedIDs = Set<UUID>()
        if let data = UserDefaults.standard.data(forKey: learnedKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            learnedIDs = Set(ids)
        }

        // Compare against the end of the return day rather than the raw endDate:
        // date-only itineraries store endDate at midnight, so a same-day return would
        // otherwise be marked completed at 00:00 while the user is still traveling —
        // and dedup makes that early signal permanent.
        let cal = Calendar.current
        let ended = trips.filter { trip in
            guard !learnedIDs.contains(trip.id) else { return false }
            let endOfReturnDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: trip.endDate)) ?? trip.endDate
            return endOfReturnDay < now
        }
        guard !ended.isEmpty else { return }

        for trip in ended {
            let city = trip.destination
                .components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces) ?? trip.destination
            let attrs = ["city": city]
            TravelProfileStore.shared.record(.tripCompleted, value: city, attributes: attrs, source: "home")
            TravelProfileStore.shared.record(.placeVisited, value: city, attributes: attrs, source: "home")
            learnedIDs.insert(trip.id)
        }

        if let data = try? JSONEncoder().encode(Array(learnedIDs)) {
            UserDefaults.standard.set(data, forKey: learnedKey)
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

    /// True when the next flight is < 90 minutes away and the user hasn't
    /// checked in yet — drives the pulsing red gate marker on Home.
    var isGateClosingSoon: Bool {
        guard let item = nextFlightItem else { return false }
        let minutes = item.startDate.timeIntervalSinceNow / 60
        guard minutes > 0, minutes <= 90 else { return false }
        let flightId = parsedFlightNumber
        return !CheckInStateStore.isCheckedIn(flightNumber: flightId, departure: item.startDate)
    }

    var destinationLocalTimeString: String {
        guard destinationTimeZone != nil else { return "" }
        // Uses a dedicated formatter whose timeZone tracks destinationTimeZone,
        // so the shared timeFormatter is never mutated during render.
        return destinationTimeFormatter.string(from: Date())
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
        guard let location = locations.first else {
            locationContinuation?.resume(throwing: CLError(.locationUnknown))
            locationContinuation = nil
            return
        }
        locationContinuation?.resume(returning: location)
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
