// File: JetSetter ProTests/BookingSyncMappingTests.swift
//
// How a confirmed backend booking becomes itinerary items and wallet passes.
// Syncing runs on every launch and foreground, so the properties that matter
// are idempotence (the same booking twice never duplicates), in-place updates
// (an airline schedule change moves the existing item), and not clobbering what
// the traveler added since (a gate, a seat, notes).
//
// These run on the pure mapper and never touch the stores.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct BookingSyncMappingTests {

    // MARK: - Fixtures

    private func confirmed() throws -> BackendBooking {
        try BackendFixtures.decode(BackendBooking.self, BackendFixtures.booking)
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }()

    private func utc(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    /// A round trip LAS -> ATL (2 Nov) and ATL -> LAS (5 Nov), nonstop each way.
    private func roundTrip() throws -> BackendBooking {
        var booking = try confirmed()
        let outbound = try #require(booking.slices.first)
        var back = outbound
        back.origin = outbound.destination
        back.destination = outbound.origin
        back.segments = outbound.segments.map { segment in
            var copy = segment
            copy.origin = segment.destination
            copy.destination = segment.origin
            copy.flightNumber = "DL1424"
            copy.departingAt = "2026-11-05T17:00:00"
            copy.arrivingAt = "2026-11-05T19:30:00"
            return copy
        }
        booking.slices = [outbound, back]
        return booking
    }

    // MARK: - Items

    @Test func aConfirmedBookingBecomesOneFlightItemWithAirportLocalTimes() throws {
        let items = BookingItineraryMapper.itineraryItems(for: try confirmed())
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.type == .flight)
        #expect(item.title == "Delta Air Lines DL1423")
        #expect(item.location == "LAS → ATL")
        #expect(item.confirmationNumber == "ABC123")
        #expect(item.bookingProvider == "Delta Air Lines")
        // 09:05 Las Vegas (UTC-8 after the 1 Nov fall-back) and 16:15 Atlanta (UTC-5).
        #expect(item.startDate == (try utc("2026-11-02T17:05:00Z")))
        #expect(item.endDate == (try utc("2026-11-02T21:15:00Z")))
        #expect(item.flightDetails?.flightNumber == "DL1423")
        #expect(item.flightDetails?.originCode == "LAS")
        #expect(item.flightDetails?.destinationCode == "ATL")
        #expect(item.flightDetails?.terminal == "1")
        #expect(item.flightDetails?.gate == nil)
        // The app's single flight-number parser reads the title.
        #expect(TravelStore.extractFlightNumber(from: item.title) == "DL1423")
    }

    @Test func theOrderTotalIsRecordedOnceNotPerSegment() throws {
        let items = BookingItineraryMapper.itineraryItems(for: try roundTrip())
        #expect(items.count == 2)
        #expect(items[0].cost == BookingCost(amount: 245.30, currencyCode: "USD"))
        #expect(items[1].cost == nil)
    }

    @Test func aConnectingSliceBecomesOneItemPerFlightNumber() throws {
        var booking = try confirmed()
        var slice = try #require(booking.slices.first)
        var second = try #require(slice.segments.first)
        second.flightNumber = "DL445"
        slice.segments.append(second)
        slice.stops = 1
        booking.slices = [slice]

        let items = BookingItineraryMapper.itineraryItems(for: booking)
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)).count == 2)
        #expect(items.map { $0.flightDetails?.flightNumber } == ["DL1423", "DL445"])
    }

    @Test func idsAreStableAcrossRunsAndDifferentPerOrder() throws {
        let booking = try confirmed()
        let first = BookingItineraryMapper.itineraryItems(for: booking)
        let second = BookingItineraryMapper.itineraryItems(for: booking)
        #expect(first.map(\.id) == second.map(\.id))

        var other = booking
        other.duffelOrderId = "ord_SOMETHING_ELSE"
        #expect(BookingItineraryMapper.itineraryItems(for: other).map(\.id) != first.map(\.id))

        let a = BookingItineraryMapper.stableUUID("seed")
        #expect(a == BookingItineraryMapper.stableUUID("seed"))
        #expect(a != BookingItineraryMapper.stableUUID("seed2"))
        // RFC 4122 layout: version nibble 5, variant bits 10.
        let bytes = a.uuid
        #expect(bytes.6 >> 4 == 5)
        #expect(bytes.8 >> 6 == 0b10)
    }

    @Test func aBookingWithoutAnOrderIdIsKeyedByItsBackendId() throws {
        var booking = try confirmed()
        booking.duffelOrderId = nil
        #expect(BookingItineraryMapper.syncKey(for: booking) == "booking-3b1f6d0e-7a54-4c1e-9d3a-0f2b8a6c1e55")
    }

    /// A time that can't be read is skipped, never replaced with an invented one.
    @Test func segmentsWithUnreadableTimesProduceNoItem() throws {
        var booking = try confirmed()
        booking.slices[0].segments[0].departingAt = "soon"
        #expect(BookingItineraryMapper.itineraryItems(for: booking).isEmpty)
        var trips: [Trip] = []
        #expect(BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar) == nil)
        #expect(trips.isEmpty)
    }

    @Test func testBookingsAreLabelledSoTheyAreNeverMistakenForRealOnes() throws {
        var booking = try confirmed()
        booking.testMode = true
        let item = try #require(BookingItineraryMapper.itineraryItems(for: booking).first)
        #expect(item.title.hasSuffix("(TEST)"))
        #expect(item.notes?.contains("Test booking") == true)
        let pass = try #require(BookingItineraryMapper.walletItems(for: booking, tripID: nil).first)
        #expect(pass.title.hasSuffix("(TEST)"))
    }

    // MARK: - Placing into trips

    @Test func syncingTwiceNeverDuplicates() throws {
        let booking = try confirmed()
        var trips: [Trip] = []

        let first = try #require(BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar))
        #expect(first.createdTrip)
        #expect(first.changed)
        #expect(trips.count == 1)
        #expect(trips[0].items.count == 1)

        let second = try #require(BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar))
        #expect(!second.createdTrip)
        #expect(!second.changed)
        #expect(second.tripID == first.tripID)
        #expect(trips.count == 1)
        #expect(trips[0].items.count == 1)
    }

    @Test func aNewTripIsNamedAfterTheDestinationOfARoundTrip() throws {
        var trips: [Trip] = []
        BookingItineraryMapper.apply(try roundTrip(), to: &trips, calendar: calendar)
        let trip = try #require(trips.first)
        #expect(trip.name == "Trip to Atlanta")
        #expect(trip.destination == "Atlanta")
        #expect(trip.items.count == 2)
        #expect(BookingItineraryMapper.tripDestination(for: try confirmed()) == "Atlanta")
    }

    @Test func flightsGoIntoTheTripWhoseDatesOverlap() throws {
        let existing = Trip(
            name: "Atlanta board meeting", destination: "Atlanta",
            startDate: try utc("2026-11-01T08:00:00Z"), endDate: try utc("2026-11-06T08:00:00Z"))
        let unrelated = Trip(
            name: "Spring", destination: "Tokyo",
            startDate: try utc("2027-03-01T08:00:00Z"), endDate: try utc("2027-03-09T08:00:00Z"))
        var trips = [unrelated, existing]

        let placement = try #require(BookingItineraryMapper.apply(try roundTrip(), to: &trips, calendar: calendar))
        #expect(!placement.createdTrip)
        #expect(placement.tripID == existing.id)
        #expect(trips.count == 2)
        #expect(trips.first { $0.id == existing.id }?.items.count == 2)
        #expect(trips.first { $0.id == unrelated.id }?.items.isEmpty == true)
    }

    @Test func anAirlineScheduleChangeUpdatesTheItemInPlace() throws {
        var booking = try confirmed()
        var trips: [Trip] = []
        BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar)
        let original = try #require(trips[0].items.first)

        // The airline retimes the flight to 10:20.
        booking.slices[0].segments[0].departingAt = "2026-11-02T10:20:00"
        booking.slices[0].segments[0].arrivingAt = "2026-11-02T17:30:00"
        let placement = try #require(BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar))

        #expect(placement.changed)
        #expect(trips.count == 1)
        #expect(trips[0].items.count == 1)
        let updated = try #require(trips[0].items.first)
        #expect(updated.id == original.id)
        #expect(updated.startDate == (try utc("2026-11-02T18:20:00Z")))
        #expect(updated.endDate == (try utc("2026-11-02T22:30:00Z")))
    }

    /// The defect this guards: a re-sync overwriting a gate or note the
    /// traveler (or check-in) added after the first sync.
    @Test func aResyncKeepsWhatWasAddedSinceTheFirstSync() throws {
        let booking = try confirmed()
        var trips: [Trip] = []
        BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar)

        trips[0].items[0].flightDetails?.gate = "C22"
        trips[0].items[0].flightDetails?.seat = "3A"
        trips[0].items[0].notes = "Window seat requested"
        trips[0].items[0].calendarEventIdentifier = "EVENT-1"

        BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar)
        let item = try #require(trips[0].items.first)
        #expect(item.flightDetails?.gate == "C22")
        #expect(item.flightDetails?.seat == "3A")
        #expect(item.notes == "Window seat requested")
        #expect(item.calendarEventIdentifier == "EVENT-1")
        #expect(item.flightDetails?.flightNumber == "DL1423")
    }

    @Test func aCancelledBookingRemovesOnlyItsOwnFlights() throws {
        let booking = try confirmed()
        var trips: [Trip] = []
        BookingItineraryMapper.apply(booking, to: &trips, calendar: calendar)
        let mine = ItineraryItem(title: "Dinner", type: .restaurant, startDate: try utc("2026-11-03T02:00:00Z"))
        trips[0].items.append(mine)

        #expect(BookingItineraryMapper.remove(booking, from: &trips))
        #expect(trips[0].items.map(\.id) == [mine.id])
        #expect(!BookingItineraryMapper.remove(booking, from: &trips))
    }

    // MARK: - Wallet

    @Test func eachSegmentGetsABoardingPassCarryingTheOrderIdentifiers() throws {
        let tripID = UUID()
        let passes = BookingItineraryMapper.walletItems(for: try confirmed(), tripID: tripID)
        let pass = try #require(passes.first)
        #expect(passes.count == 1)
        #expect(pass.itemType == .boardingPass)
        #expect(pass.tripId == tripID)
        #expect(pass.title == "DL1423 · LAS → ATL")
        #expect(pass.confirmationNumber == "ABC123")
        #expect(pass.date == (try utc("2026-11-02T17:05:00Z")))
        #expect(pass.rawData["duffel_order_id"] == "ord_0000AaBbCc")
        #expect(pass.rawData["booking_reference"] == "ABC123")
        #expect(pass.rawData["flight_number"] == "DL1423")
        #expect(pass.rawData["iata_code"] == "DL")
        #expect(pass.rawData["departure_airport"] == "LAS")
        #expect(pass.rawData["arrival_airport"] == "ATL")
        #expect(pass.rawData["terminal"] == "1")
        #expect(pass.rawData["airline"] == "Delta Air Lines")
        // Unknown things stay absent rather than blank or guessed.
        #expect(pass.rawData["gate"] == nil)
        #expect(pass.rawData["seat_number"] == nil)
        #expect(pass.rawData["barcode_message"] == nil)
        #expect(pass.rawData.values.allSatisfy { !$0.isEmpty })
        // It stays "active" until the flight has landed.
        #expect(pass.rawData["end_date"] == "2026-11-02T21:15:00Z")
    }

    @Test func walletIdsAreStableAndDistinctFromItineraryIds() throws {
        let booking = try confirmed()
        let a = BookingItineraryMapper.walletItems(for: booking, tripID: nil)
        let b = BookingItineraryMapper.walletItems(for: booking, tripID: UUID())
        #expect(a.map(\.id) == b.map(\.id))
        #expect(Set(a.map(\.id)).isDisjoint(with: BookingItineraryMapper.itineraryItems(for: booking).map(\.id)))
    }

    @Test func aWalletResyncKeepsAGateBarcodeAndSeatAddedSince() throws {
        let booking = try confirmed()
        let fresh = try #require(BookingItineraryMapper.walletItems(for: booking, tripID: nil).first)
        var existing = fresh
        existing.rawData["gate"] = "C22"
        existing.rawData["barcode_message"] = "M1LOVELACE/ADA..."
        existing.rawData["seat_number"] = "3A"
        existing.rawData["terminal"] = "OLD"

        var changed = booking
        changed.slices[0].segments[0].originTerminal = "3"
        let refreshed = try #require(BookingItineraryMapper.walletItems(for: changed, tripID: UUID()).first)
        let merged = BookingItineraryMapper.merge(existing: existing, with: refreshed)

        #expect(merged.id == fresh.id)
        #expect(merged.rawData["gate"] == "C22")
        #expect(merged.rawData["barcode_message"] == "M1LOVELACE/ADA...")
        #expect(merged.rawData["seat_number"] == "3A")
        #expect(merged.rawData["terminal"] == "3")
        #expect(merged.tripId == refreshed.tripId)
    }

    @Test func aSoleTravelersSeatIsUsedButASharedBookingNeverGuessesOne() throws {
        var booking = try confirmed()
        booking.passengers[0].seat = "12C"
        #expect(BookingItineraryMapper.itineraryItems(for: booking).first?.flightDetails?.seat == "12C")
        #expect(BookingItineraryMapper.walletItems(for: booking, tripID: nil).first?.rawData["seat_number"] == "12C")

        var second = booking.passengers[0]
        second.id = "pas_2"
        second.seat = "12D"
        booking.passengers.append(second)
        #expect(BookingItineraryMapper.itineraryItems(for: booking).first?.flightDetails?.seat == nil)
        #expect(BookingItineraryMapper.walletItems(for: booking, tripID: nil).first?.rawData["seat_number"] == nil)
    }
}
