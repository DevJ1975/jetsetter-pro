// File: Core/Intents/SpotlightEntities.swift
//
// What Spotlight (and Siri, which searches the same index) knows about the
// traveler's plans: upcoming trips (`TripEntity`, declared in AppIntents.swift)
// and the bookings inside them (`BookingEntity`). `SpotlightIndexer` donates
// them; tapping a result runs the matching OpenIntent below.
//
// Deliberately left out of the index: confirmation numbers. A booking
// reference plus a surname is enough to change or cancel a booking on most
// airline sites, and the index is a copy outside the app's own storage.
// Searching "Delta" or "Atlanta" finds the booking; the reference is one tap
// away inside the app.

import AppIntents
import CoreSpotlight
import Foundation

// MARK: - Trip

extension TripEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.startDate = startDate
        attributes.endDate = endDate
        attributes.namedLocation = destination
        attributes.keywords = [destination, name]
        return attributes
    }
}

/// Opens a trip picked in Spotlight or Shortcuts.
struct OpenTripIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Trip"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Trip")
    var target: TripEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigate(to: .itinerary)
        return .result()
    }
}

// MARK: - Booking

/// One flight, stay, car or plan inside a trip.
struct BookingEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Booking")
    static let defaultQuery = BookingQuery()

    let id: UUID
    let title: String
    let kind: ItineraryItemType
    let tripName: String
    let startDate: Date
    let endDate: Date?
    let flightNumber: String?
    let originCode: String?
    let destinationCode: String?
    let provider: String?
    let location: String?
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: DisplayRepresentation.Image(systemName: kind.systemImage, isTemplate: true)
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.startDate = startDate
        attributes.endDate = endDate
        attributes.namedLocation = location
        attributes.keywords = [kind.displayName, tripName, provider, flightNumber, originCode, destinationCode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return attributes
    }

    init(item: ItineraryItem, trip: Trip) {
        let flight = item.type == .flight
        let route = flight ? ConfirmationTextParser.parse(item.title) : nil
        id = item.id
        title = item.title
        kind = item.type
        tripName = trip.name
        startDate = item.startDate
        endDate = item.endDate
        flightNumber = flight
            ? (Self.nonEmpty(item.flightDetails?.flightNumber) ?? TravelStore.extractFlightNumber(from: item.title))
            : nil
        originCode = Self.nonEmpty(item.flightDetails?.originCode) ?? route?.originCode
        destinationCode = Self.nonEmpty(item.flightDetails?.destinationCode) ?? route?.destinationCode
        provider = Self.nonEmpty(item.bookingProvider) ?? Self.nonEmpty(item.flightDetails?.airline)
        location = Self.nonEmpty(item.location)
        subtitle = Self.summary(
            kind: item.type, start: item.startDate, end: item.endDate,
            originCode: originCode, destinationCode: destinationCode
        )
    }

    /// "Flight · LAS to ATL · Sep 14, 2026 at 9:05 AM". A flight's time is the
    /// wall clock at its departure airport, like the airline's own itinerary,
    /// so a traveler searching from Atlanta still sees the Las Vegas time.
    /// "to" rather than an arrow, so VoiceOver and Siri don't read "arrow".
    /// Other bookings use the phone's calendar, like the rest of the app.
    static func summary(
        kind: ItineraryItemType,
        start: Date,
        end: Date?,
        originCode: String?,
        destinationCode: String?,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var parts = [kind.displayName]
        switch kind {
        case .flight:
            if let originCode, let destinationCode { parts.append("\(originCode) to \(destinationCode)") }
            parts.append(AppDateFormatters.airportTime(start, iata: originCode, style: .dateTime, locale: locale))
        case .hotel:
            var range = start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
            if let end { range += " – " + end.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)) }
            parts.append(range)
        case .activity, .transport, .restaurant:
            parts.append(start.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)))
        }
        return parts.joined(separator: " · ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed != "—" else { return nil }
        return trimmed
    }
}

struct BookingQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BookingEntity] {
        let trips = TravelStore.loadTrips()
        return trips.flatMap { trip in
            trip.items.filter { identifiers.contains($0.id) }.map { BookingEntity(item: $0, trip: trip) }
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [BookingEntity] {
        let needle = string.lowercased()
        return SpotlightSelection.bookings(from: TravelStore.loadTrips(), now: Date())
            .map { BookingEntity(item: $0.item, trip: $0.trip) }
            .filter { entity in
                [entity.title, entity.tripName, entity.provider, entity.location, entity.flightNumber]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(needle) }
            }
    }

    @MainActor
    func suggestedEntities() async throws -> [BookingEntity] {
        SpotlightSelection.bookings(from: TravelStore.loadTrips(), now: Date())
            .prefix(5)
            .map { BookingEntity(item: $0.item, trip: $0.trip) }
    }
}

/// Opens a booking picked in Spotlight or Shortcuts. The itinerary is where
/// bookings live today; when the router gains a per-booking destination this
/// is the one line to change.
struct OpenBookingIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Booking"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Booking")
    var target: BookingEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigate(to: .itinerary)
        return .result()
    }
}

// MARK: - What gets indexed

/// The trips and bookings worth finding: anything not over yet. Past trips
/// drop out of the index on the next re-index, so Spotlight doesn't keep
/// offering last spring's hotel.
enum SpotlightSelection {

    /// Active and upcoming trips, soonest first.
    static func trips(from trips: [Trip], now: Date) -> [Trip] {
        trips.filter { $0.endDate >= now }.sorted { $0.startDate < $1.startDate }
    }

    /// Bookings that haven't finished (a hotel stay already under way still
    /// counts), soonest first.
    static func bookings(from trips: [Trip], now: Date) -> [(item: ItineraryItem, trip: Trip)] {
        self.trips(from: trips, now: now)
            .flatMap { trip in trip.items.map { (item: $0, trip: trip) } }
            .filter { ($0.item.endDate ?? $0.item.startDate) >= now }
            .sorted { $0.item.startDate < $1.item.startDate }
    }
}
