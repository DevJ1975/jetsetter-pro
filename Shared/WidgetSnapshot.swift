// File: Shared/WidgetSnapshot.swift
//
// The single payload the app hands its widgets through the App Group. The
// widget extension can't compile `TravelStore`, SwiftData or the itinerary
// models, so the app (`WidgetBridge`) projects what the widgets need into
// these plain value types and the widgets only ever read this.
//
// Compiled into BOTH the app and the widget extension: `Shared/` is a
// synchronized folder in both targets (see `project.pbxproj`), the same way
// `FlightActivityAttributes.swift` gets there. Everything is explicitly
// `nonisolated` because the app target defaults to main-actor isolation and
// the widget target doesn't; without it the `Codable` conformances would be
// main-actor-bound in one target and not the other.
//
// Versioning. Version 1 was the original Next Trip payload: four top-level
// fields (`name`, `destination`, `startDate`, `endDate`) and no version key.
// Version 2 keeps writing those four fields for the active-or-next trip, under
// the same UserDefaults key, so the original Next Trip widget keeps working
// without an edit, and it decodes a version 1 payload into a one-trip
// snapshot. Decoding is tolerant everywhere: a missing or mistyped optional
// field becomes nil, and a list row that can't be decoded is dropped instead
// of failing the whole snapshot. A widget that can't read its data shows the
// empty state; it never crashes.
//
// Privacy. The snapshot sits in a shared container that any process in the App
// Group can read, so it never carries a confirmation number (PNR), a
// passenger name or a barcode payload. Seat and gate are included because the
// widgets show them, and the views mark them `.privacySensitive()`.

import Foundation

nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {

    /// The layout this file writes. Bump it when a field changes meaning, and
    /// keep decoding every older version.
    static let currentSchemaVersion = 2

    static let maxTrips = 3
    static let maxFlightsPerTrip = 3
    static let maxItemsPerTrip = 6

    /// Version the payload was written with. Absent in version 1, so a decoded
    /// version 1 payload reads 1 here.
    var schemaVersion: Int
    /// When the app last changed this payload's content.
    var generatedAt: Date
    /// IANA zone of the traveler's home airport (Settings → Home airport), or
    /// nil when they haven't set one. "Home" clocks fall back to "Here".
    var homeTimeZoneID: String?
    /// Up to three trips: an active trip first, then the next upcoming ones.
    var trips: [TripSummary]
    /// When to leave for the airport for one flight, from the last live
    /// departure briefing. Nil when there isn't a current one.
    var leaveBy: LeaveBy?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, homeTimeZoneID, trips, leaveBy
        // Version 1 fields, still written for the original Next Trip widget.
        case name, destination, startDate, endDate
    }

    // MARK: - Trip

    nonisolated struct TripSummary: Codable, Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        /// What the traveler typed for the destination, e.g. "Atlanta, GA".
        var destination: String
        var startDate: Date
        var endDate: Date
        /// Arrival airport of the trip's first (outbound) flight, when known.
        var destinationCode: String?
        /// That airport's IANA zone. Nil means unknown, never the device zone.
        var destinationTimeZoneID: String?
        /// Up to three flights that hadn't landed when this was written,
        /// soonest first. Widgets pick the current one at render time, so the
        /// next leg appears after a landing without waiting for the app.
        var flights: [FlightLeg]
        /// Up to six itinerary items from the start of the publishing day
        /// onward, soonest first. Widgets filter to "today" at render time.
        var items: [DayItem]
        /// Current conditions at `destinationCode`, when the app had them.
        var weather: Weather?

        private enum CodingKeys: String, CodingKey {
            case id, name, destination, startDate, endDate, destinationCode,
                 destinationTimeZoneID, flights, items, weather
        }
    }

    // MARK: - Flight

    nonisolated struct FlightLeg: Codable, Equatable, Sendable, Identifiable {
        /// The itinerary item's id.
        var id: UUID
        /// "DL1423". Nil when the item has no recognisable flight number.
        var flightNumber: String?
        /// Marketing airline name as the traveler or the booking gave it.
        var airline: String?
        var originCode: String?
        var originCity: String?
        var destinationCode: String?
        var destinationCity: String?
        var departure: Date
        /// Scheduled arrival. Nil when the itinerary doesn't have one.
        var arrival: Date?
        var originTimeZoneID: String?
        var destinationTimeZoneID: String?
        /// Nil means unknown and renders as "—". Gate, terminal and seat are
        /// often only known hours before departure.
        var gate: String?
        var terminal: String?
        var seat: String?
        /// The Travel Wallet boarding pass for this flight, if one was saved.
        /// Only the id: the pass's barcode never leaves the app.
        var walletPassID: UUID?
        /// When online check-in opens. Nil when the carrier's window isn't
        /// known; check-in windows differ by airline, so it's never guessed.
        var checkInOpensAt: Date?
        /// Estimated time to be at the gate for boarding.
        var boardingEstimate: Date?

        private enum CodingKeys: String, CodingKey {
            case id, flightNumber, airline, originCode, originCity, destinationCode, destinationCity,
                 departure, arrival, originTimeZoneID, destinationTimeZoneID, gate, terminal, seat,
                 walletPassID, checkInOpensAt, boardingEstimate
        }
    }

    // MARK: - Itinerary item

    nonisolated struct DayItem: Codable, Equatable, Sendable, Identifiable {

        nonisolated enum Kind: String, Codable, Sendable {
            case flight, hotel, activity, transport, restaurant, other

            /// A kind written by a newer app version reads as `.other`
            /// instead of failing the row.
            init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Kind(rawValue: raw) ?? .other
            }

            var systemImage: String {
                switch self {
                case .flight:     return "airplane"
                case .hotel:      return "bed.double.fill"
                case .activity:   return "star.fill"
                case .transport:  return "car.fill"
                case .restaurant: return "fork.knife"
                case .other:      return "calendar"
                }
            }
        }

        var id: UUID
        var kind: Kind
        /// The item's title with any confirmation number removed.
        var title: String
        var start: Date
        /// IANA zone the traveler will be in at `start`. Nil when unknown;
        /// the widget then renders in the device's zone without a label.
        var timeZoneID: String?

        private enum CodingKeys: String, CodingKey {
            case id, kind, title, start, timeZoneID
        }
    }

    // MARK: - Weather

    nonisolated struct Weather: Codable, Equatable, Sendable {
        var temperatureFahrenheit: Double
        /// SF Symbol name.
        var symbolName: String
        var condition: String
        /// True for WeatherKit data, which must be shown with the Apple
        /// Weather mark. Open-Meteo data is shown without it, as in the app.
        var isAppleWeather: Bool
        var observedAt: Date

        /// Older conditions are hidden rather than shown as current.
        static let maxAge: TimeInterval = 6 * 3_600

        func isCurrent(at date: Date) -> Bool {
            date.timeIntervalSince(observedAt) < Self.maxAge
        }
    }

    // MARK: - Leave-by

    nonisolated struct LeaveBy: Codable, Equatable, Sendable {
        /// The `FlightLeg.id` this leave-by time belongs to.
        var flightID: UUID
        var leaveAt: Date
        /// False when the drive time was an estimate rather than live traffic.
        var usesLiveTraffic: Bool
        var computedAt: Date
        /// After this the briefing is too old to quote and the widget hides it
        /// (`DepartureBriefing.maxAge` on the app side).
        var expiresAt: Date

        /// A traffic reading describes the roads when it was taken. After this
        /// long the time is still the best we have, but it's labelled "est.".
        static let liveReadingLifetime: TimeInterval = 30 * 60

        /// Whether to present the time as a live-traffic reading at `date`.
        func isLive(at date: Date) -> Bool {
            usesLiveTraffic && date.timeIntervalSince(computedAt) <= Self.liveReadingLifetime
        }
    }
}

// MARK: - Convenience

extension WidgetSnapshot {

    /// An empty, current-version snapshot (no trips).
    nonisolated static func empty(generatedAt: Date) -> WidgetSnapshot {
        WidgetSnapshot(schemaVersion: currentSchemaVersion, generatedAt: generatedAt,
                       homeTimeZoneID: nil, trips: [], leaveBy: nil)
    }

    /// The trip a widget shows: the configured one when it's still in the
    /// snapshot, otherwise the active-or-next trip.
    nonisolated func trip(preferring id: UUID?) -> TripSummary? {
        if let id, let chosen = trips.first(where: { $0.id == id }) { return chosen }
        return trips.first
    }

    /// The flights in scope for a widget: one trip's when a trip was chosen,
    /// every trip's otherwise, soonest first.
    nonisolated func flights(forTrip id: UUID?) -> [FlightLeg] {
        if let id, let chosen = trips.first(where: { $0.id == id }) { return chosen.flights }
        return trips.flatMap(\.flights).sorted { $0.departure < $1.departure }
    }
}

extension WidgetSnapshot.FlightLeg {

    /// The instant the flight stops being "the next flight": its scheduled
    /// arrival, or its departure when the arrival isn't known.
    nonisolated var endsAt: Date { arrival ?? departure }
}

// MARK: - Tolerant decoding

// Each `init(from:)` lives in an extension so the synthesized memberwise
// initializers stay available (`CodingKeys` stay in the type bodies, where
// the synthesized `encode(to:)` uses them). Required fields are the ones a row is useless
// without (ids, names, dates); everything else decodes with `try?` so a
// mistyped value becomes nil instead of an error.

extension WidgetSnapshot {

    /// Stands in for the missing id of the single trip in a version 1 payload.
    nonisolated static let legacyTripID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        schemaVersion = version
        generatedAt = (try? c.decodeIfPresent(Date.self, forKey: .generatedAt)) ?? .distantPast
        homeTimeZoneID = try? c.decodeIfPresent(String.self, forKey: .homeTimeZoneID)
        leaveBy = try? c.decodeIfPresent(LeaveBy.self, forKey: .leaveBy)

        if let list = try? c.decodeIfPresent(LossyList<TripSummary>.self, forKey: .trips) {
            trips = list.elements
        } else if version == 1,
                  let name = try? c.decode(String.self, forKey: .name),
                  let destination = try? c.decode(String.self, forKey: .destination),
                  let start = try? c.decode(Date.self, forKey: .startDate),
                  let end = try? c.decode(Date.self, forKey: .endDate) {
            trips = [TripSummary(id: Self.legacyTripID, name: name, destination: destination,
                                 startDate: start, endDate: end, destinationCode: nil,
                                 destinationTimeZoneID: nil, flights: [], items: [], weather: nil)]
        } else {
            trips = []
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encodeIfPresent(homeTimeZoneID, forKey: .homeTimeZoneID)
        try c.encode(trips, forKey: .trips)
        try c.encodeIfPresent(leaveBy, forKey: .leaveBy)
        // The original Next Trip widget decodes exactly these four fields.
        if let first = trips.first {
            try c.encode(first.name, forKey: .name)
            try c.encode(first.destination, forKey: .destination)
            try c.encode(first.startDate, forKey: .startDate)
            try c.encode(first.endDate, forKey: .endDate)
        }
    }
}

extension WidgetSnapshot.TripSummary {

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        destination = (try? c.decodeIfPresent(String.self, forKey: .destination)) ?? ""
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        destinationCode = try? c.decodeIfPresent(String.self, forKey: .destinationCode)
        destinationTimeZoneID = try? c.decodeIfPresent(String.self, forKey: .destinationTimeZoneID)
        flights = (try? c.decodeIfPresent(LossyList<WidgetSnapshot.FlightLeg>.self, forKey: .flights))?.elements ?? []
        items = (try? c.decodeIfPresent(LossyList<WidgetSnapshot.DayItem>.self, forKey: .items))?.elements ?? []
        weather = try? c.decodeIfPresent(WidgetSnapshot.Weather.self, forKey: .weather)
    }
}

extension WidgetSnapshot.FlightLeg {

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        departure = try c.decode(Date.self, forKey: .departure)
        flightNumber = try? c.decodeIfPresent(String.self, forKey: .flightNumber)
        airline = try? c.decodeIfPresent(String.self, forKey: .airline)
        originCode = try? c.decodeIfPresent(String.self, forKey: .originCode)
        originCity = try? c.decodeIfPresent(String.self, forKey: .originCity)
        destinationCode = try? c.decodeIfPresent(String.self, forKey: .destinationCode)
        destinationCity = try? c.decodeIfPresent(String.self, forKey: .destinationCity)
        arrival = try? c.decodeIfPresent(Date.self, forKey: .arrival)
        originTimeZoneID = try? c.decodeIfPresent(String.self, forKey: .originTimeZoneID)
        destinationTimeZoneID = try? c.decodeIfPresent(String.self, forKey: .destinationTimeZoneID)
        gate = try? c.decodeIfPresent(String.self, forKey: .gate)
        terminal = try? c.decodeIfPresent(String.self, forKey: .terminal)
        seat = try? c.decodeIfPresent(String.self, forKey: .seat)
        walletPassID = try? c.decodeIfPresent(UUID.self, forKey: .walletPassID)
        checkInOpensAt = try? c.decodeIfPresent(Date.self, forKey: .checkInOpensAt)
        boardingEstimate = try? c.decodeIfPresent(Date.self, forKey: .boardingEstimate)
    }
}

extension WidgetSnapshot.DayItem {

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(Date.self, forKey: .start)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .other
        timeZoneID = try? c.decodeIfPresent(String.self, forKey: .timeZoneID)
    }
}

/// Decodes an array, skipping elements that fail instead of failing the array.
nonisolated private struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                decoded.append(element)
            } else {
                // A failed decode doesn't advance the container, so consume
                // the bad element explicitly or the loop never ends.
                _ = try? container.decode(Skipped.self)
            }
        }
        elements = decoded
    }

    nonisolated private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

// MARK: - Storage

/// Reads and writes the snapshot in the shared App Group defaults.
nonisolated enum WidgetSnapshotStore {

    static let appGroupID = "group.DevJ.JetSetter-Pro"
    /// The key the original one-trip snapshot used. Kept so the original Next
    /// Trip widget reads the version 2 payload's legacy fields unchanged.
    static let snapshotKey = "jetsetter_next_trip_snapshot"

    /// The App Group's defaults. Until the App Group capability is on both App
    /// IDs, the app and the widget each get their own domain, so widgets show
    /// their empty state; nothing crashes.
    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// ISO 8601 dates, which the original Next Trip widget decodes, and sorted
    /// keys so equal snapshots encode to identical bytes.
    static func encode(_ snapshot: WidgetSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func load(from defaults: UserDefaults) -> WidgetSnapshot? {
        defaults.data(forKey: snapshotKey).flatMap(decode)
    }
}

// MARK: - Kinds and links

/// Widget kind strings, shared so the app reloads exactly the widgets that exist.
nonisolated enum WidgetKinds {
    /// The original Next Trip widget (`WidgetExtension/NextTripWidget.swift`).
    static let nextTrip = "NextTripWidget"
    static let nextFlight = "NextFlightWidget"
    static let leaveBy = "LeaveByWidget"
    static let tripDay = "TripDayWidget"
    static let destinationClock = "DestinationClockWidget"

    static let all = [nextTrip, nextFlight, leaveBy, tripDay, destinationClock]
}

/// The `jetsetterpro://` deep links widgets open. The app's router owns
/// handling them; these only build them, so both sides agree on the shape.
nonisolated enum WidgetLinks {
    static let scheme = "jetsetterpro"

    /// The active-or-next trip.
    static var nextTrip: URL? { URL(string: "\(scheme)://trip/next") }
    /// The add-a-trip flow.
    static var newTrip: URL? { URL(string: "\(scheme)://trip/new") }

    /// One trip, for a widget configured to follow it.
    static func trip(_ id: UUID) -> URL? {
        URL(string: "\(scheme)://trip/\(id.uuidString)")
    }

    /// Flight detail for "DL1423". Nil for an empty or unencodable number.
    static func flight(_ flightNumber: String) -> URL? {
        let compact = flightNumber.filter { !$0.isWhitespace }
        guard !compact.isEmpty,
              let encoded = compact.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "\(scheme)://flight/\(encoded)")
    }

    /// A boarding pass in the Travel Wallet.
    static func walletPass(_ id: UUID) -> URL? {
        URL(string: "\(scheme)://wallet/pass/\(id.uuidString)")
    }
}
