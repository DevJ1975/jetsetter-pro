// File: JetSetter ProTests/TripDayTests.swift
//
// The trip-day pieces that aren't routing: when Home starts the Live
// Activity, that the backend's Live Activity payload still decodes, the Live
// Activity's time and gate rules, spoken airport names, and which wallet pass
// belongs to a flight.
//
// Instants are built from ISO 8601 strings in UTC and zones are explicit, so
// results are the same on a CI runner in UTC and a phone in Atlanta.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct TripDayTests {

    private func instant(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    // MARK: - Live Activity start rule

    @Test func homeStartsTheCardWithinFourHoursOnceCheckedIn() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let threeHoursOut = now.addingTimeInterval(3 * 3600)
        #expect(FlightLiveActivityService.shouldStartFromHome(departure: threeHoursOut, isCheckedIn: true, now: now))
    }

    @Test func homeWaitsForCheckIn() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let oneHourOut = now.addingTimeInterval(3600)
        #expect(!FlightLiveActivityService.shouldStartFromHome(departure: oneHourOut, isCheckedIn: false, now: now))
    }

    /// Defect: the card started at check-in, often a day out, and iOS ends a
    /// Live Activity after eight hours, so it was gone before the flight.
    @Test func homeDoesNotStartACardThatWouldExpireBeforeTheFlight() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let fiveHoursOut = now.addingTimeInterval(5 * 3600)
        #expect(!FlightLiveActivityService.shouldStartFromHome(departure: fiveHoursOut, isCheckedIn: true, now: now))
    }

    @Test func homeStillStartsTheCardForADelayedFlightJustPastItsTime() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(FlightLiveActivityService.shouldStartFromHome(
            departure: now.addingTimeInterval(-30 * 60), isCheckedIn: true, now: now))
        #expect(!FlightLiveActivityService.shouldStartFromHome(
            departure: now.addingTimeInterval(-2 * 3600), isCheckedIn: true, now: now))
    }

    // MARK: - Live Activity payload

    /// The Django backend sends `content-state` with only the original fields,
    /// and ActivityKit decodes it with a default `JSONDecoder`. The fields added
    /// for the redesign must not break that.
    @Test func theBackendsContentStateStillDecodes() throws {
        let json = #"{"gate":"C22","terminal":"1","status":"onTime","estimatedDeparture":780000000,"delayMinutes":null}"#
        let state = try JSONDecoder().decode(FlightActivityState.self, from: Data(json.utf8))
        #expect(state.gate == "C22")
        #expect(state.status == .onTime)
        #expect(state.estimatedDeparture == Date(timeIntervalSinceReferenceDate: 780_000_000))
        #expect(state.seat == nil)
        #expect(state.estimatedArrival == nil)
    }

    @Test func theNewContentStateFieldsRoundTrip() throws {
        let state = FlightActivityState(
            gate: nil, terminal: "S", status: .delayed,
            estimatedDeparture: Date(timeIntervalSinceReferenceDate: 780_000_000),
            delayMinutes: 50, seat: "3A",
            estimatedArrival: Date(timeIntervalSinceReferenceDate: 780_015_000)
        )
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(FlightActivityState.self, from: data) == state)
        // Far below ActivityKit's 4 KB limit for state plus attributes.
        #expect(data.count < 1024)
    }

    // MARK: - Live Activity text rules

    @Test func aRedEyeArrivesTheNextDay() throws {
        // LAX 22:00 PDT on 14 Sep → JFK 06:30 EDT on 15 Sep.
        let offset = FlightActivityFormatting.arrivalDayOffset(
            departure: try instant("2026-09-15T05:00:00Z"), in: try zone("America/Los_Angeles"),
            arrival: try instant("2026-09-15T10:30:00Z"), in: try zone("America/New_York")
        )
        #expect(offset == 1)
        #expect(FlightActivityFormatting.dayOffsetLabel(offset) == "+1")
    }

    @Test func flyingEastAcrossTheDateLineArrivesTheDayBefore() throws {
        // HND 08:00 JST on 15 Sep → HNL 20:00 HST on 14 Sep.
        let offset = FlightActivityFormatting.arrivalDayOffset(
            departure: try instant("2026-09-14T23:00:00Z"), in: try zone("Asia/Tokyo"),
            arrival: try instant("2026-09-15T06:00:00Z"), in: try zone("Pacific/Honolulu")
        )
        #expect(offset == -1)
        #expect(FlightActivityFormatting.dayOffsetLabel(offset) == "\u{2212}1")
    }

    @Test func aDaytimeFlightHasNoDayOffset() throws {
        // LAS 09:00 PDT → ATL 16:05 EDT, same day despite the three-hour change.
        let offset = FlightActivityFormatting.arrivalDayOffset(
            departure: try instant("2026-09-14T16:00:00Z"), in: try zone("America/Los_Angeles"),
            arrival: try instant("2026-09-14T20:05:00Z"), in: try zone("America/New_York")
        )
        #expect(offset == 0)
        #expect(FlightActivityFormatting.dayOffsetLabel(offset) == nil)
    }

    @Test func departureTimeReadsInTheAirportsZone() throws {
        let posix = Locale(identifier: "en_US_POSIX")
        let text = FlightActivityFormatting.time(try instant("2026-09-14T16:05:00Z"),
                                                 in: try zone("America/Los_Angeles"), locale: posix)
        #expect(text.contains("9:05"))
    }

    @Test func theIslandShowsTheGateOnlyInTheLastFortyFiveMinutes() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(FlightActivityFormatting.showsGateInCompact(gate: "C22", departure: now.addingTimeInterval(44 * 60), now: now))
        #expect(!FlightActivityFormatting.showsGateInCompact(gate: "C22", departure: now.addingTimeInterval(46 * 60), now: now))
    }

    @Test func anUnknownGateNeverReplacesTheCountdown() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let soon = now.addingTimeInterval(10 * 60)
        for gate in [nil, "", "—", "-", "TBD"] {
            #expect(!FlightActivityFormatting.showsGateInCompact(gate: gate, departure: soon, now: now))
        }
    }

    @Test func unknownValuesReadAsADash() {
        #expect(FlightActivityFormatting.display(nil) == "—")
        #expect(FlightActivityFormatting.display("  ") == "—")
        #expect(FlightActivityFormatting.display("tbd") == "—")
        #expect(FlightActivityFormatting.display(" 3A ") == "3A")
    }

    /// A `ClosedRange` whose bounds are inverted traps, and a card rendered
    /// after its departure time would otherwise build one.
    @Test func theCountdownRangeIsNeverInverted() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let past = now.addingTimeInterval(-600)
        let range = FlightActivityFormatting.countdownRange(to: past, now: now)
        #expect(range.lowerBound == past)
        #expect(range.upperBound == past)
        let ring = FlightActivityFormatting.ringRange(to: now)
        #expect(ring.upperBound.timeIntervalSince(ring.lowerBound) == 4 * 3600)
    }

    @Test func routeProgressFollowsTheScheduleAndNeverGuesses() {
        let departure = Date(timeIntervalSince1970: 1_790_000_000)
        let arrival = departure.addingTimeInterval(4 * 3600)
        #expect(FlightActivityFormatting.routeProgress(departure: departure, arrival: arrival,
                                                       now: departure.addingTimeInterval(-60)) == 0)
        #expect(FlightActivityFormatting.routeProgress(departure: departure, arrival: arrival,
                                                       now: departure.addingTimeInterval(2 * 3600)) == 0.5)
        #expect(FlightActivityFormatting.routeProgress(departure: departure, arrival: arrival,
                                                       now: arrival.addingTimeInterval(60)) == 1)
        #expect(FlightActivityFormatting.routeProgress(departure: departure, arrival: nil,
                                                       now: arrival) == 0)
    }

    // MARK: - Spoken airport names

    @Test func routesAreSpokenAsCities() {
        #expect(AirportNames.spokenRoute(from: "LAS", to: "ATL") == "Las Vegas to Atlanta")
        #expect(AirportNames.spokenName(for: " jfk ") == "New York JFK")
    }

    @Test func anUnknownCodeIsSpelledOutRatherThanGuessed() {
        #expect(AirportNames.spokenName(for: "XYZ") == nil)
        #expect(AirportNames.spokenRoute(from: "LAS", to: "XYZ") == "Las Vegas to X Y Z")
    }

    @Test func everyNamedAirportIsInTheCoordinateTable() {
        // `AirportCoordinates` keeps its table private; it has 87 hubs, and
        // every name here must be one of them (and so have a time zone).
        #expect(AirportNames.knownCodes.count == 87)
        for code in AirportNames.knownCodes {
            #expect(AirportCoordinates.isKnown(code), "\(code)")
            #expect(AirportCoordinates.timeZone(for: code) != nil, "\(code)")
        }
    }

    // MARK: - Boarding pass matching

    private func pass(_ flight: String?, at date: Date, type: WalletItemType = .boardingPass) -> WalletItem {
        var raw: [String: String] = [:]
        if let flight { raw["flight_number"] = flight }
        return WalletItem(itemType: type, title: flight ?? "Pass", date: date, rawData: raw)
    }

    /// A commuter has last Monday's pass for the same flight in the wallet;
    /// it must never be the one that opens at the gate.
    @Test func theSameFlightNumberLastWeekIsNotThisFlightsPass() throws {
        let departure = try instant("2026-09-14T16:05:00Z")
        let lastWeek = pass("DL1423", at: departure.addingTimeInterval(-7 * 86_400))
        let thisWeek = pass("DL1423", at: departure)
        let other = pass("UA55", at: departure)
        let match = BoardingPassMatcher.match(in: [lastWeek, other, thisWeek],
                                              flightNumber: "DL 1423", departure: departure)
        #expect(match?.id == thisWeek.id)
    }

    @Test func leadingZerosAndSpacesDontHideAMatch() throws {
        let departure = try instant("2026-09-14T16:05:00Z")
        let scanned = pass("JL006", at: departure.addingTimeInterval(-10 * 3600))
        #expect(BoardingPassMatcher.match(in: [scanned], flightNumber: "JL 6", departure: departure)?.id == scanned.id)
    }

    @Test func aPassWithoutAFlightNumberMatchesOnTheSameDay() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try zone("UTC")
        let departure = try instant("2026-09-14T16:05:00Z")
        let dateOnly = pass(nil, at: try instant("2026-09-14T00:00:00Z"))
        let dayBefore = pass(nil, at: try instant("2026-09-13T00:00:00Z"))
        let match = BoardingPassMatcher.match(in: [dayBefore, dateOnly], flightNumber: "DL1423",
                                              departure: departure, calendar: utc)
        #expect(match?.id == dateOnly.id)
    }

    @Test func noPassMeansNoMatch() throws {
        let departure = try instant("2026-09-14T16:05:00Z")
        let hotel = pass("DL1423", at: departure, type: .hotelReservation)
        #expect(BoardingPassMatcher.match(in: [hotel], flightNumber: "DL1423", departure: departure) == nil)
        #expect(BoardingPassMatcher.match(in: [], flightNumber: nil, departure: nil) == nil)
    }

    // MARK: - Departure alert airport

    /// Defect: the 2-hours-before alert fell back to the trip's destination
    /// and told the traveler their LAS → ATL flight "departs Atlanta".
    @Test func theDepartureAlertNamesTheOriginAirport() {
        let typed = ItineraryItem(title: "DL1423", type: .flight, startDate: Date(),
                                  flightDetails: FlightBookingDetails(originCode: "las"))
        #expect(TravelNotificationScheduler.originIATA(of: typed) == "LAS")

        let routed = ItineraryItem(title: "DL1423", type: .flight, startDate: Date(), location: "LAS → ATL")
        #expect(TravelNotificationScheduler.originIATA(of: routed) == "LAS")

        let freeText = ItineraryItem(title: "DL1423", type: .flight, startDate: Date(), location: "Terminal 1")
        #expect(TravelNotificationScheduler.originIATA(of: freeText) == nil)
    }
}
