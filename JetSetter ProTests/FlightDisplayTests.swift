// File: JetSetter ProTests/FlightDisplayTests.swift
//
// Offer and booking -> display mapping. The point of these tests is time zones:
// a flight time is a wall clock at an airport, so the same booking must read the
// same on a phone in Las Vegas, Atlanta or Tokyo, and an overnight arrival must
// carry its day offset. Also money formatting by currency, the "—"-not-a-guess
// rule for missing fare terms, and the wording of the money-related states.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct FlightDisplayTests {

    private let us = Locale(identifier: "en_US")
    private let gb = Locale(identifier: "en_GB")

    private func offer() throws -> BackendOffer {
        try BackendFixtures.decode(BackendOffer.self, BackendFixtures.offer)
    }

    private func airport(_ code: String, zone: String?, city: String? = nil) -> BackendAirport {
        BackendAirport(iataCode: code, name: nil, cityName: city, timeZone: zone)
    }

    private func segment(from origin: BackendAirport, to destination: BackendAirport,
                         departing: String, arriving: String, number: String? = "XX1") -> BackendSegment {
        BackendSegment(marketingCarrier: BackendCarrier(name: "Test Air", iataCode: "XX", logoUrl: nil),
                       operatingCarrier: nil, flightNumber: number, origin: origin, destination: destination,
                       departingAt: departing, arrivingAt: arriving, duration: nil, aircraft: nil,
                       originTerminal: nil, destinationTerminal: nil)
    }

    // MARK: - Airport time zones

    @Test func departureShowsInTheOriginZoneAndArrivalInTheDestinationZone() throws {
        let slice = try #require(try offer().slices.first)
        let display = FlightDisplay.slice(slice, locale: gb)
        // ICU spells a 24-hour morning time with or without a leading zero.
        #expect(["09:05", "9:05"].contains(display.departureTime))
        #expect(display.arrivalTime == "16:15")
        #expect(display.arrivalDayOffset == 0)
        #expect(display.arrivalDayLabel == nil)
        #expect(display.routeLabel == "LAS → ATL")
        #expect(display.spokenRoute == "Las Vegas to Atlanta")
        #expect(display.durationText != nil)
        #expect(display.stopsText == "Nonstop")
    }

    @Test func twelveHourLocalesGetAMPMTimes() throws {
        let slice = try #require(try offer().slices.first)
        let display = FlightDisplay.slice(slice, locale: us)
        #expect(display.departureTime.hasPrefix("9:05"))
        #expect(display.arrivalTime.hasPrefix("4:15"))
    }

    /// The wall-clock strings become the right absolute instants: 09:05 in Las
    /// Vegas on 2 November 2026 (after daylight time ended, UTC-8) is 17:05Z,
    /// and 16:15 in Atlanta (UTC-5) is 21:15Z. The difference is the 4h10m flight.
    @Test func wallClockTimesBecomeAbsoluteInstantsUsingTheAirportZone() throws {
        let segment = try #require(try offer().slices.first?.segments.first)
        let las = try #require(BackendDates.zone(for: segment.origin))
        let atl = try #require(BackendDates.zone(for: segment.destination))
        let departure = try #require(BackendDates.instant(segment.departingAt, in: las))
        let arrival = try #require(BackendDates.instant(segment.arrivingAt, in: atl))

        let iso = ISO8601DateFormatter()
        #expect(departure == iso.date(from: "2026-11-02T17:05:00Z"))
        #expect(arrival == iso.date(from: "2026-11-02T21:15:00Z"))
        #expect(arrival.timeIntervalSince(departure) == 4 * 3600 + 10 * 60)
    }

    /// When the server omits a zone the app's own airport table supplies it,
    /// and when neither knows, the wall clock is shown as sent.
    @Test func zoneFallsBackToTheAirportTableThenToTheWallClock() {
        #expect(BackendDates.zone(for: airport("LAS", zone: nil))?.identifier == "America/Los_Angeles")
        #expect(BackendDates.zone(for: airport("LAS", zone: "Not/AZone"))?.identifier == "America/Los_Angeles")
        #expect(BackendDates.zone(for: airport("ZZZ", zone: nil)) == nil)

        let unknown = airport("ZZZ", zone: nil)
        #expect(["09:05", "9:05"].contains(FlightDisplay.wallTime("2026-11-02T09:05:00", at: unknown, locale: gb)))
    }

    // MARK: - Day offsets

    @Test func overnightArrivalCarriesAPlusOne() {
        let las = airport("LAS", zone: "America/Los_Angeles", city: "Las Vegas")
        let atl = airport("ATL", zone: "America/New_York", city: "Atlanta")
        let slice = BackendSlice(origin: las, destination: atl, duration: "PT4H45M", stops: 0, segments: [
            segment(from: las, to: atl, departing: "2026-11-02T22:30:00", arriving: "2026-11-03T06:15:00")
        ])
        let display = FlightDisplay.slice(slice, locale: gb)
        #expect(display.arrivalDayOffset == 1)
        #expect(display.arrivalDayLabel == "+1")
        #expect(["22:30 – 06:15 +1", "22:30 – 6:15 +1"].contains(display.timeRange))
    }

    @Test func dateLineCrossingsCanLandTwoDaysLaterOrTheDayBefore() {
        #expect(BackendDates.dayOffset(departing: "2026-11-02T23:00:00", arriving: "2026-11-04T05:00:00") == 2)
        // Tokyo Saturday night to Honolulu Saturday morning: same calendar day.
        #expect(BackendDates.dayOffset(departing: "2026-11-07T20:00:00", arriving: "2026-11-07T09:00:00") == 0)
        // Auckland early Sunday to Los Angeles Saturday afternoon: one day earlier.
        #expect(BackendDates.dayOffset(departing: "2026-11-08T01:00:00", arriving: "2026-11-07T14:00:00") == -1)
        #expect(FlightDisplay.dayOffsetLabel(-1) == "−1")
        #expect(FlightDisplay.dayOffsetLabel(2) == "+2")
        #expect(FlightDisplay.dayOffsetLabel(0) == nil)
    }

    @Test func dayOffsetIsComputedFromLocalDatesSoDaylightTimeCannotShiftIt() {
        // The night US clocks fall back (1 November 2026): a 01:30 departure
        // and a 07:00 arrival are still the same calendar day.
        #expect(BackendDates.dayOffset(departing: "2026-11-01T01:30:00", arriving: "2026-11-01T07:00:00") == 0)
    }

    // MARK: - Connections

    @Test func connectionsListStopsAndFlagTightLayovers() {
        let las = airport("LAS", zone: "America/Los_Angeles")
        let slc = airport("SLC", zone: "America/Denver", city: "Salt Lake City")
        let atl = airport("ATL", zone: "America/New_York")
        let first = segment(from: las, to: slc, departing: "2026-11-02T09:00:00", arriving: "2026-11-02T11:30:00")
        let second = segment(from: slc, to: atl, departing: "2026-11-02T12:10:00", arriving: "2026-11-02T17:30:00")
        let slice = BackendSlice(origin: las, destination: atl, duration: "PT6H30M", stops: 1, segments: [first, second])

        #expect(FlightDisplay.stopsText(slice) == "1 stop · SLC")
        // Lands 11:30 Denver, departs 12:10 Denver: 40 minutes, under the
        // 60-minute tight-connection line.
        let layover = FlightDisplay.layoverMinutes(from: first, to: second)
        #expect(layover == 40)
        #expect((layover ?? .max) < FlightDisplay.tightConnectionMinutes)
    }

    // MARK: - Flight numbers

    @Test func flightNumbersKeepTheFullDesignator() {
        let las = airport("LAS", zone: nil), atl = airport("ATL", zone: nil)
        #expect(FlightDisplay.flightNumber(segment(from: las, to: atl, departing: "", arriving: "", number: "DL1423"), fallbackCarrier: nil) == "DL1423")
        #expect(FlightDisplay.flightNumber(segment(from: las, to: atl, departing: "", arriving: "", number: "b6 715"), fallbackCarrier: nil) == "B6715")
        // A bare number is prefixed with the carrier so TravelStore can parse it.
        #expect(FlightDisplay.flightNumber(segment(from: las, to: atl, departing: "", arriving: "", number: "1423"), fallbackCarrier: nil) == "XX1423")
        #expect(FlightDisplay.flightNumber(segment(from: las, to: atl, departing: "", arriving: "", number: nil), fallbackCarrier: nil) == nil)
        #expect(TravelStore.extractFlightNumber(from: "Delta Air Lines DL1423") == "DL1423")
    }

    // MARK: - Fare terms

    @Test func missingFareTermsAreNeverShownAsPermissive() {
        #expect(FlightDisplay.refundSummary(nil, locale: us) == "Refund terms not provided")
        let unknown = BackendConditions(refundBeforeDeparture: BackendConditionRule(allowed: nil, penaltyAmount: nil, penaltyCurrency: nil),
                                        changeBeforeDeparture: nil)
        #expect(FlightDisplay.refundSummary(unknown, locale: us) == "Refund terms not provided")
        #expect(FlightDisplay.changeSummary(unknown, locale: us) == "Change terms not provided")
        #expect(FlightDisplay.baggageSummary([]) == "Baggage not specified")
    }

    @Test func fareTermsSummariseRefundChangeAndBags() throws {
        let conditions = try #require(try offer().conditions)
        #expect(FlightDisplay.refundSummary(conditions, locale: us) == "Refundable · $50.00 fee")
        #expect(FlightDisplay.changeSummary(conditions, locale: us) == "Free changes")

        let strict = BackendConditions(
            refundBeforeDeparture: BackendConditionRule(allowed: false, penaltyAmount: nil, penaltyCurrency: nil),
            changeBeforeDeparture: BackendConditionRule(allowed: false, penaltyAmount: nil, penaltyCurrency: nil))
        #expect(FlightDisplay.refundSummary(strict, locale: us) == "Non-refundable")
        #expect(FlightDisplay.changeSummary(strict, locale: us) == "Changes not allowed")

        #expect(FlightDisplay.baggageSummary([BackendBaggage(type: "checked", quantity: 1), BackendBaggage(type: "carry_on", quantity: 1)])
                == "1 checked bag · 1 carry-on")
        #expect(FlightDisplay.baggageSummary([BackendBaggage(type: "checked", quantity: 0)]) == "No checked bag")
        #expect(FlightDisplay.cabinName("premium_economy") == "Premium Economy")
        #expect(FlightDisplay.cabinName(nil) == nil)
    }

    // MARK: - Sorting

    @Test func offersSortByPriceDurationAndStopsWithPriceAsTheTiebreak() {
        func offer(_ id: String, _ price: String, minutes: String, stops: Int) -> BackendOffer {
            let a = airport("LAS", zone: nil), b = airport("ATL", zone: nil)
            return BackendOffer(id: id, airline: BackendCarrier(name: nil, iataCode: nil, logoUrl: nil),
                                totalAmount: price, totalCurrency: "USD",
                                slices: [BackendSlice(origin: a, destination: b, duration: minutes, stops: stops)])
        }
        let cheapSlow = offer("cheapSlow", "100.00", minutes: "PT9H", stops: 2)
        let midFast = offer("midFast", "150.00", minutes: "PT4H", stops: 0)
        let priceyFast = offer("priceyFast", "300.00", minutes: "PT4H", stops: 0)
        let offers = [priceyFast, cheapSlow, midFast]

        #expect(FlightDisplay.sorted(offers, by: .price).map(\.id) == ["cheapSlow", "midFast", "priceyFast"])
        #expect(FlightDisplay.sorted(offers, by: .duration).map(\.id) == ["midFast", "priceyFast", "cheapSlow"])
        #expect(FlightDisplay.sorted(offers, by: .stops).map(\.id) == ["midFast", "priceyFast", "cheapSlow"])
    }

    // MARK: - Money, durations, dates

    @Test func moneyFormatsByCurrencyAndNeverGuesses() {
        #expect(BackendMoney.display("245.30", currency: "USD", locale: us) == "$245.30")
        let yen = BackendMoney.display("24530", currency: "JPY", locale: us)
        #expect(yen.contains("24,530") && !yen.contains("."))
        let dinar = BackendMoney.display("12.345", currency: "KWD", locale: us)
        #expect(dinar.contains("12.345"))

        #expect(BackendMoney.display(nil, currency: "USD") == "—")
        #expect(BackendMoney.display("abc", currency: "USD") == "—")
        #expect(BackendMoney.display("10.00", currency: nil) == "—")
    }

    @Test func pricesCompareNumericallyNotAsText() {
        #expect(BackendMoney.isSameAmount("245.3", "245.30"))
        #expect(!BackendMoney.isSameAmount("245.30", "245.31"))
        #expect(BackendMoney.isZero("0.00"))
        #expect(BackendMoney.isZero(nil))
        #expect(!BackendMoney.isZero("0.01"))
        #expect(BackendMoney.double("245.30") == 245.30)
    }

    @Test func isoDurationsParse() {
        #expect(BackendDuration.minutes("PT4H10M") == 250)
        #expect(BackendDuration.minutes("PT45M") == 45)
        #expect(BackendDuration.minutes("PT2H") == 120)
        #expect(BackendDuration.minutes("P1DT2H") == 1560)
        #expect(BackendDuration.minutes("4 hours") == nil)
        #expect(BackendDuration.minutes("PT") == nil)
        #expect(BackendDuration.minutes(nil) == nil)
        #expect(BackendDuration.display("PT4H10M") != nil)
    }

    @Test func timestampsParseWithZonesAndMicroseconds() throws {
        let iso = ISO8601DateFormatter()
        let expected = try #require(iso.date(from: "2026-11-02T14:05:00Z"))
        #expect(BackendDates.parseTimestamp("2026-11-02T14:05:00Z") == expected)
        #expect(BackendDates.parseTimestamp("2026-11-02T14:05:00.123456Z") == expected)
        #expect(BackendDates.parseTimestamp("2026-11-02T19:35:00+05:30") == expected)
        #expect(BackendDates.parseTimestamp("2026-11-02T09:05:00-05:00") == expected)
        #expect(BackendDates.parseTimestamp("2026-11-02T14:05:00") == expected)
        #expect(BackendDates.parseTimestamp("not a date") == nil)
    }

    // MARK: - Status wording

    @Test func failedBookingsSayWhetherMoneyWasRefunded() throws {
        let refunded = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.bookingJSON(
            status: "failed", detail: "Airline rejected the order",
            refund: #"{"amount": "245.30", "currency": "USD", "status": "succeeded"}"#))
        #expect(BookingStatusCopy.explanation(refunded) == "Airline rejected the order")
        #expect(BookingStatusCopy.refundLine(refunded, locale: us) == "$245.30 was refunded to your card.")

        let unrefunded = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.bookingJSON(status: "failed"))
        let line = try #require(BookingStatusCopy.refundLine(unrefunded, locale: us))
        #expect(line.contains("No refund is recorded"))
        #expect(!line.lowercased().contains("was refunded"))
    }

    @Test func pendingRefundsAndExpiredBookingsAreWordedHonestly() throws {
        let pending = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.bookingJSON(
            status: "cancelled", refund: #"{"amount": "120.00", "currency": "USD", "status": "pending"}"#))
        #expect(BookingStatusCopy.refundLine(pending, locale: us) == "A refund of $120.00 is on its way to your card.")

        let expired = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.bookingJSON(status: "expired"))
        #expect(BookingStatusCopy.refundLine(expired) == "You weren't charged.")

        let confirmed = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.bookingJSON(status: "confirmed"))
        #expect(BookingStatusCopy.refundLine(confirmed) == nil)
        #expect(BookingStatusCopy.title(.pendingPayment) == "Waiting for payment")
    }

    @Test func updatedTextIsRelative() {
        let now = Date()
        let text = BookingsText.updated(now.addingTimeInterval(-12 * 60), now: now, locale: us)
        #expect(text.hasPrefix("Updated "))
        #expect(text.contains("12"))
    }
}
