// File: Core/Services/Persistence/WidgetBridge.swift
//
// App-side feed for every widget. The widget extension runs in its own process
// and can't compile `TravelStore`, SwiftData or the itinerary models, so this
// projects what the widgets need into a `WidgetSnapshot` (Shared/), writes it
// to the App Group, and asks WidgetKit to reload timelines, but only when the
// encoded snapshot actually changed: reloads come out of a daily budget.
//
// Three paths publish:
//   • `publishNextTrip(from:)`, called synchronously by `JetDataStore.writeTrips`
//     and at launch. The store calls it while holding its lock, so this path
//     must stay synchronous and must not read `TravelStore` (that would
//     deadlock). Everything it reads is a cheap synchronous cache.
//   • The `.jetSetterTripsChanged` subscription installed on the first publish,
//     which republishes from `TravelStore` after the lock is released and
//     refreshes destination weather, which needs an async fetch.
//   • `publishLeaveBy(from:)`, called by `DepartureBriefing` whenever the
//     optimizer caches a live briefing.
//
// What never reaches the snapshot: confirmation numbers (PNRs), passenger
// names, barcode payloads and notes. Titles are scrubbed of any confirmation
// number before they're copied. A boarding pass contributes its id (for the
// deep link) and, when the itinerary has no seat, its seat.
//
// App Group: until `group.DevJ.JetSetter-Pro` is on both App IDs, the app and
// the widget each get their own defaults domain, so widgets show their empty
// state. Nothing crashes.

import Foundation
import CoreLocation
import WidgetKit

enum WidgetBridge {

    /// Shared defaults if the App Group is available, else this process's own.
    static var sharedDefaults: UserDefaults {
        WidgetSnapshotStore.sharedDefaults()
    }

    /// The Travel Wallet's on-device cache (`WalletViewModel`, demo seeding).
    /// Read synchronously, as OfflineKit does, because the publish path runs
    /// inside the trip store's lock and can't await `LocalDataService`.
    private static let walletCacheKey = "jetsetter_wallet_items"

    /// Destination weather is fetched once a trip is under way or starts
    /// within this long, the same window OfflineKit pre-caches in.
    private static let weatherLeadTime: TimeInterval = 48 * 3_600
    /// Don't refetch weather more often than this for the widgets.
    private static let weatherRefreshInterval: TimeInterval = 30 * 60

    private static var tripsObserver: NSObjectProtocol?
    private static var weatherTask: Task<Void, Never>?

    // MARK: - Publishing

    /// Rebuilds the snapshot from `trips` and reloads widget timelines if
    /// anything a widget shows changed. Computed from the passed array, never
    /// via `TravelStore`, because `JetDataStore` calls this mid-write.
    static func publishNextTrip(from trips: [Trip], now: Date = Date()) {
        startObservingTripChanges()
        let defaults = sharedDefaults
        let previous = WidgetSnapshotStore.load(from: defaults)
        let snapshot = makeSnapshot(from: trips, now: now, inputs: currentInputs(previous: previous))
        write(snapshot, to: defaults, now: now)
        refreshDestinationWeather(for: snapshot, now: now)
    }

    /// Mirrors the app's one cached live briefing into the snapshot, so the
    /// Leave By widget quotes the same time as Home and Siri. A briefing for a
    /// flight the snapshot doesn't hold clears the old leave-by, exactly as
    /// the app itself only ever has one.
    static func publishLeaveBy(from briefing: DepartureBriefing, now: Date = Date()) {
        let defaults = sharedDefaults
        guard var snapshot = WidgetSnapshotStore.load(from: defaults) else { return }
        snapshot.leaveBy = leaveBy(from: briefing, flights: snapshot.trips.flatMap(\.flights), now: now)
        write(snapshot, to: defaults, now: now)
    }

    /// Subscribes once to trip changes. Installed by the first publish (the
    /// launch publish in `JetSetter_ProApp`), so no other file has to know.
    static func startObservingTripChanges() {
        guard tripsObserver == nil else { return }
        tripsObserver = NotificationCenter.default.addObserver(
            forName: .jetSetterTripsChanged, object: nil, queue: .main
        ) { _ in
            // Posted after the store's lock is released, so reading the
            // store here is safe. An unchanged snapshot costs no reload.
            Task { @MainActor in WidgetBridge.publishNextTrip(from: TravelStore.loadTrips()) }
        }
    }

    // MARK: - Writing

    /// Writes `snapshot` and reloads every widget kind, unless its content is
    /// identical to what's stored. Returns whether it wrote.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot, to defaults: UserDefaults, now: Date = Date()) -> Bool {
        let stored = defaults.data(forKey: WidgetSnapshotStore.snapshotKey)
        guard hasChanged(snapshot, comparedTo: stored) else { return false }
        var stamped = snapshot
        stamped.generatedAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        guard let data = WidgetSnapshotStore.encode(stamped) else { return false }
        defaults.set(data, forKey: WidgetSnapshotStore.snapshotKey)
        for kind in WidgetKinds.all {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        return true
    }

    /// Whether `snapshot` differs from the stored bytes in anything but its
    /// timestamp. Compared as encoded JSON, not as values: the store keeps
    /// whole-second ISO 8601 dates, so a trip date with a fractional second
    /// would never compare equal to its own stored copy and every publish
    /// would spend a reload.
    static func hasChanged(_ snapshot: WidgetSnapshot, comparedTo stored: Data?) -> Bool {
        guard let stored, let previous = WidgetSnapshotStore.decode(stored) else { return true }
        var candidate = snapshot
        candidate.generatedAt = previous.generatedAt
        return WidgetSnapshotStore.encode(candidate) != stored
    }

    // MARK: - Building the snapshot

    /// Everything besides the trips that goes into a snapshot. Gathered from
    /// synchronous caches by `currentInputs`, or supplied directly by tests.
    struct Inputs {
        var homeAirport: String?
        var walletItems: [WalletItem]
        var briefing: DepartureBriefing?
        var previous: WidgetSnapshot?
        var deviceTimeZone: TimeZone
    }

    private static func currentInputs(previous: WidgetSnapshot?) -> Inputs {
        Inputs(
            homeAirport: UserPreferences.shared.homeAirport,
            walletItems: CodableDefaults.load([WalletItem].self, forKey: walletCacheKey) ?? [],
            briefing: DepartureBriefing.current(),
            previous: previous,
            deviceTimeZone: .current
        )
    }

    /// The snapshot for `trips` at `now`. Pure apart from the lookup tables
    /// it consults, so tests can pin exactly what reaches the App Group.
    static func makeSnapshot(from trips: [Trip], now: Date, inputs: Inputs) -> WidgetSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = inputs.deviceTimeZone
        let startOfToday = calendar.startOfDay(for: now)
        let secrets = confirmationNumbers(in: trips, wallet: inputs.walletItems)

        let summaries = upcomingTrips(trips, now: now)
            .prefix(WidgetSnapshot.maxTrips)
            .map { tripSummary($0, now: now, startOfToday: startOfToday, secrets: secrets, inputs: inputs) }

        let flights = summaries.flatMap(\.flights)
        return WidgetSnapshot(
            schemaVersion: WidgetSnapshot.currentSchemaVersion,
            generatedAt: now,
            homeTimeZoneID: airportCode(inputs.homeAirport).flatMap(AirportCoordinates.timeZone(for:))?.identifier,
            trips: Array(summaries),
            leaveBy: inputs.briefing.flatMap { leaveBy(from: $0, flights: flights, now: now) }
        )
    }

    /// Active trips first (by start), then upcoming ones (by start).
    static func upcomingTrips(_ trips: [Trip], now: Date) -> [Trip] {
        let active = trips.filter { $0.startDate <= now && $0.endDate >= now }
        let upcoming = trips.filter { $0.startDate > now }
        return active.sorted { $0.startDate < $1.startDate } + upcoming.sorted { $0.startDate < $1.startDate }
    }

    private static func tripSummary(
        _ trip: Trip,
        now: Date,
        startOfToday: Date,
        secrets: Set<String>,
        inputs: Inputs
    ) -> WidgetSnapshot.TripSummary {
        let sorted = trip.sortedItems
        let legs = sorted.filter { $0.type == .flight }
            .map { flightLeg($0, secrets: secrets, wallet: inputs.walletItems) }
        // The destination is where the outbound (chronologically first)
        // flight lands, as OfflineKit decides it.
        let outbound = legs.first
        let items = sorted.filter { $0.startDate >= startOfToday }
            .prefix(WidgetSnapshot.maxItemsPerTrip)
            .map { dayItem($0, legs: legs, secrets: secrets) }

        return WidgetSnapshot.TripSummary(
            id: trip.id,
            name: scrubbed(trip.name, removing: secrets, fallback: "Trip"),
            destination: scrubbed(trip.destination, removing: secrets, fallback: ""),
            startDate: trip.startDate,
            endDate: trip.endDate,
            destinationCode: outbound?.destinationCode,
            destinationTimeZoneID: outbound?.destinationTimeZoneID,
            flights: Array(legs.filter { $0.endsAt > now }.prefix(WidgetSnapshot.maxFlightsPerTrip)),
            items: Array(items),
            weather: carriedWeather(from: inputs.previous, tripID: trip.id,
                                    destinationCode: outbound?.destinationCode, now: now)
        )
    }

    private static func flightLeg(_ item: ItineraryItem, secrets: Set<String>, wallet: [WalletItem]) -> WidgetSnapshot.FlightLeg {
        let details = item.flightDetails
        // The title first: Home, Siri, check-in and the optimizer's briefing
        // all key a flight by the number in its title, so the leave-by match
        // and the deep link agree with them.
        let flightNumber = normalizedFlightNumber(item.title) ?? normalizedFlightNumber(details?.flightNumber)
        let route = routeCodes(for: item)
        let pass = boardingPass(for: flightNumber, departure: item.startDate, in: wallet)

        // Boarding estimate: when LeaveByPlanner plans to have the traveler at
        // the gate, with the international buffer when the airports are known
        // to sit in different countries.
        let international = LeaveByPlanner.isInternational(originIATA: route.origin, destinationIATA: route.destination)
        let boardingBuffer = international
            ? LeaveByPlanner.internationalBoardingBufferMinutes
            : LeaveByPlanner.domesticBoardingBufferMinutes

        return WidgetSnapshot.FlightLeg(
            id: item.id,
            flightNumber: flightNumber,
            airline: cleaned(details?.airline, removing: secrets) ?? cleaned(item.bookingProvider, removing: secrets),
            originCode: route.origin,
            originCity: city(for: route.origin),
            destinationCode: route.destination,
            destinationCity: city(for: route.destination),
            departure: item.startDate,
            // An arrival at or before departure is a data-entry slip, not a
            // time to show.
            arrival: item.endDate.flatMap { $0 > item.startDate ? $0 : nil },
            originTimeZoneID: route.origin.flatMap(AirportCoordinates.timeZone(for:))?.identifier,
            destinationTimeZoneID: route.destination.flatMap(AirportCoordinates.timeZone(for:))?.identifier,
            gate: item.resolvedGate,
            terminal: item.resolvedTerminal,
            seat: nonEmpty(details?.seat) ?? nonEmpty(pass?.seatNumber),
            walletPassID: pass?.id,
            // Check-in windows differ by carrier, and the carrier table lives
            // privately in `CheckInService`; until it's exposed, no time is
            // published rather than a one-size-fits-all 24 hours.
            checkInOpensAt: nil,
            boardingEstimate: item.startDate.addingTimeInterval(-TimeInterval(boardingBuffer) * 60)
        )
    }

    private static func dayItem(_ item: ItineraryItem, legs: [WidgetSnapshot.FlightLeg], secrets: Set<String>) -> WidgetSnapshot.DayItem {
        WidgetSnapshot.DayItem(
            id: item.id,
            kind: kind(for: item.type),
            title: scrubbed(item.title, removing: secrets, fallback: item.type.displayName),
            start: item.startDate,
            timeZoneID: localZoneID(for: item, legs: legs)
        )
    }

    /// The zone the traveler is in when `item` starts. A flight leaves in its
    /// origin's zone. Anything else happens where the last flight before it
    /// landed, or, before the first flight, where that flight departs from.
    /// Nil when no flight says, and the widget then uses the device's zone.
    private static func localZoneID(for item: ItineraryItem, legs: [WidgetSnapshot.FlightLeg]) -> String? {
        if item.type == .flight {
            return legs.first { $0.id == item.id }?.originTimeZoneID
        }
        if let landed = legs.last(where: { $0.endsAt <= item.startDate }) {
            return landed.destinationTimeZoneID
        }
        return legs.first { $0.departure > item.startDate }?.originTimeZoneID
    }

    private static func kind(for type: ItineraryItemType) -> WidgetSnapshot.DayItem.Kind {
        switch type {
        case .flight:     return .flight
        case .hotel:      return .hotel
        case .activity:   return .activity
        case .transport:  return .transport
        case .restaurant: return .restaurant
        }
    }

    // MARK: - Leave-by

    /// The snapshot form of a live briefing, matched to its flight by flight
    /// number and origin. Nil when the briefing is too old to quote, names no
    /// flight in the snapshot, or its time can't be recovered exactly.
    static func leaveBy(from briefing: DepartureBriefing, flights: [WidgetSnapshot.FlightLeg], now: Date) -> WidgetSnapshot.LeaveBy? {
        guard now.timeIntervalSince(briefing.computedAt) < DepartureBriefing.maxAge,
              let wanted = normalizedFlightNumber(briefing.flightNumber)
        else { return nil }
        let origin = airportCode(briefing.originIATA)
        guard let flight = flights
            .filter({ $0.flightNumber == wanted && (origin == nil || $0.originCode == origin) && $0.departure > now })
            .min(by: { $0.departure < $1.departure }),
              let leaveAt = leaveInstant(fromLeaveBy: briefing.leaveBy, before: flight.departure)
        else { return nil }
        return WidgetSnapshot.LeaveBy(
            flightID: flight.id,
            leaveAt: leaveAt,
            // The optimizer only caches a briefing whose drive time came from
            // live traffic (`LeaveByPlanner.Plan.isDriveTimeLive`).
            usesLiveTraffic: true,
            computedAt: briefing.computedAt,
            expiresAt: briefing.computedAt.addingTimeInterval(DepartureBriefing.maxAge)
        )
    }

    /// The instant behind a briefing's leave-by text ("5:19 AM").
    ///
    /// `DepartureOptimizerService` hands `DepartureBriefing` a formatted time
    /// rather than a `Date`. The text carries no day, and the briefing can be
    /// for a flight days away, so the day comes from the flight: the leave
    /// time is the last moment before departure that reads that wall-clock
    /// time (the plan's buffers are hours, never a day). The candidate must
    /// format back to exactly the same text with the same formatter settings
    /// the optimizer used, so "now (window passed)" or any future rewording
    /// yields nil and the widget hides the leave-by rather than guess.
    static func leaveInstant(
        fromLeaveBy text: String,
        before departure: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        guard let parsed = formatter.date(from: text) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let clock = calendar.dateComponents([.hour, .minute], from: parsed)
        guard let candidate = calendar.nextDate(
                after: departure,
                matching: DateComponents(hour: clock.hour, minute: clock.minute, second: 0),
                matchingPolicy: .nextTime,
                direction: .backward),
              formatter.string(from: candidate) == text
        else { return nil }
        return candidate
    }

    // MARK: - Weather

    /// Keeps the last reading for the same trip and airport while it's still
    /// current, so a synchronous republish doesn't drop it.
    private static func carriedWeather(from previous: WidgetSnapshot?, tripID: UUID,
                                       destinationCode: String?, now: Date) -> WidgetSnapshot.Weather? {
        guard let destinationCode,
              let trip = previous?.trips.first(where: { $0.id == tripID && $0.destinationCode == destinationCode }),
              let weather = trip.weather, weather.isCurrent(at: now)
        else { return nil }
        return weather
    }

    /// Fetches current conditions at the first trip's destination once that
    /// trip is under way or close, then folds them into the stored snapshot.
    /// `WeatherService` caches for ten minutes, so this is usually the reading
    /// Home just showed, not a new network call.
    private static func refreshDestinationWeather(for snapshot: WidgetSnapshot, now: Date) {
        guard let trip = snapshot.trips.first,
              trip.startDate.timeIntervalSince(now) < weatherLeadTime,
              let code = trip.destinationCode,
              let coordinate = AirportCoordinates.coordinate(for: code)
        else { return }
        if let existing = trip.weather, now.timeIntervalSince(existing.observedAt) < weatherRefreshInterval {
            return
        }

        weatherTask?.cancel()
        weatherTask = Task {
            guard let data = try? await WeatherService.shared.fetch(
                    latitude: coordinate.latitude, longitude: coordinate.longitude),
                  !Task.isCancelled
            else { return }
            let weather = WidgetSnapshot.Weather(
                temperatureFahrenheit: data.temperatureFahrenheit,
                symbolName: data.systemIcon,
                condition: data.conditionDescription,
                isAppleWeather: data.source == .weatherKit,
                observedAt: Date()
            )
            let defaults = sharedDefaults
            guard var current = WidgetSnapshotStore.load(from: defaults),
                  let index = current.trips.firstIndex(where: { $0.id == trip.id && $0.destinationCode == code })
            else { return }
            current.trips[index].weather = weather
            write(current, to: defaults)
        }
    }

    // MARK: - Lookups

    /// Origin and destination codes for a flight item: the structured fields
    /// the Add Itinerary form saves, then the "LAS → ATL" location line. Only
    /// three-letter codes count, so a typed city name stays unknown ("—").
    private static func routeCodes(for item: ItineraryItem) -> (origin: String?, destination: String?) {
        let legs = routeLegs(item.location)
        let origin = airportCode(item.flightDetails?.originCode) ?? airportCode(legs.first)
        let destination = airportCode(item.flightDetails?.destinationCode)
            ?? (legs.count > 1 ? airportCode(legs[1]) : nil)
        return (origin, destination)
    }

    /// Splits "LAS → ATL" on the separators the itinerary sources use, the
    /// same set the Departure Optimizer accepts.
    private static func routeLegs(_ location: String?) -> [String] {
        let raw = location ?? ""
        for separator in [" → ", " -> ", " – ", " — ", " - ", "→", "->", "–", "—"] where raw.contains(separator) {
            return raw.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
    }

    /// A three-letter IATA airport code, uppercased, or nil.
    private static func airportCode(_ raw: String?) -> String? {
        guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        return code
    }

    /// City for a code from the boarding pass's table. That table echoes an
    /// unknown code back; that's not a city, so it becomes nil.
    private static func city(for code: String?) -> String? {
        guard let code, let name = BoardingPassDetailView.cityName(for: code), name != code else { return nil }
        return name
    }

    /// "DL 1423" and "Delta DL1423 to Atlanta" both become "DL1423", through
    /// the app's one flight-number parser.
    private static func normalizedFlightNumber(_ raw: String?) -> String? {
        nonEmpty(raw).flatMap { TravelStore.extractFlightNumber(from: $0) }
    }

    /// The saved boarding pass for a flight: the same flight number, dated
    /// within a day and a half of departure, so last month's pass for the same
    /// route never links.
    private static func boardingPass(for flightNumber: String?, departure: Date, in wallet: [WalletItem]) -> WalletItem? {
        guard let flightNumber else { return nil }
        return wallet
            .filter { $0.itemType == .boardingPass
                && normalizedFlightNumber($0.flightNumber) == flightNumber
                && abs($0.date.timeIntervalSince(departure)) < 36 * 3_600 }
            .min { abs($0.date.timeIntervalSince(departure)) < abs($1.date.timeIntervalSince(departure)) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// A free-text name with confirmation numbers scrubbed, or nil if empty.
    private static func cleaned(_ value: String?, removing secrets: Set<String>) -> String? {
        nonEmpty(value).flatMap { nonEmpty(scrubbed($0, removing: secrets, fallback: "")) }
    }

    // MARK: - Scrubbing

    /// Every confirmation number on the traveler's trips and wallet passes.
    /// Values under five characters are skipped so a stray "1030" can't eat
    /// a time out of a title; real PNRs and hotel confirmations are longer.
    private static func confirmationNumbers(in trips: [Trip], wallet: [WalletItem]) -> Set<String> {
        let fromTrips = trips.flatMap(\.items).compactMap { nonEmpty($0.confirmationNumber) }
        let fromWallet = wallet.compactMap { nonEmpty($0.confirmationNumber) }
        return Set((fromTrips + fromWallet).filter { $0.count >= 5 })
    }

    /// `text` with confirmation numbers removed: every known one, plus any
    /// token labelled like one ("Conf# JX7QF2", "PNR: JX7QF2", "Record locator
    /// JX7QF2"). Returns `fallback` when nothing readable is left.
    static func scrubbed(_ text: String, removing secrets: Set<String>, fallback: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"(?i:\b(?:conf(?:irmation)?|pnr|record\s+locator|booking\s+(?:ref(?:erence)?|code)|reservation\s+(?:code|number))\b)\s*(?:(?i:no\.?|number|code)\s*)?[:#]?\s*[A-Z0-9]{5,8}\b"#,
            with: "",
            options: .regularExpression
        )
        for secret in secrets {
            result = result.replacingOccurrences(of: secret, with: "", options: .caseInsensitive)
        }
        result = result
            .replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "·•-–—|,:#")))
        return result.isEmpty ? fallback : result
    }
}
