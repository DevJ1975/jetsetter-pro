// File: JetSetter ProTests/BookingCaptureTests.swift
//
// Covers the parts of off-app booking capture that run without Apple
// Intelligence: the regex fallback, the date shapes a model realistically
// emits, and the merge that layers the two results. The on-device model path
// cannot run in a test host, which is exactly why the fallback needs coverage.

import Testing
import Foundation
@testable import JetSetter_Pro

@Suite(.serialized)
struct BookingCaptureTests {

    // MARK: - Fallback extraction

    @Test func fallbackReadsAFlightConfirmation() {
        let email = """
        Your trip is confirmed
        Confirmation number: JX7QF2
        Delta Air Lines DL1423
        LAS to ATL
        Total charged: $412.30
        """
        let booking = BookingCapture.heuristicBooking(from: email)
        #expect(booking.kind == .flight)
        #expect(booking.confirmationNumber == "JX7QF2")
        #expect(booking.originCode == "LAS")
        #expect(booking.destinationCode == "ATL")
        #expect(booking.flightNumber == "DL1423")
        #expect(booking.amount == 412.30)
    }

    @Test func fallbackRecognisesHotelsAndCarsWithoutARoute() {
        let hotel = BookingCapture.heuristicBooking(from: """
        The Ritz-Carlton, Atlanta
        Booking reference: RC88421
        Check-in Thursday, check-out Sunday. 3 nights, Executive Suite.
        """)
        #expect(hotel.kind == .hotel)
        #expect(hotel.confirmationNumber == "RC88421")

        let car = BookingCapture.heuristicBooking(from: """
        Hertz rental car
        Reservation code: HZ4471A
        Pick-up location: ATL Rental Car Center. Vehicle: Tesla Model 3 or similar.
        """)
        #expect(car.kind == .carRental)
    }

    @Test func fallbackReturnsEmptyForUnrelatedText() {
        let booking = BookingCapture.heuristicBooking(from: "Reminder: team standup at 9am tomorrow.")
        #expect(booking.kind == .other)
        #expect(booking.confirmationNumber == nil)
        #expect(booking.flightNumber == nil)
        #expect(booking.isEmpty)
    }

    // MARK: - Dates

    @Test func parsesTheDateShapesAModelEmits() throws {
        let calendar = Calendar.current

        // 2026-09-14T07:00:00Z, asserted as an absolute instant.
        let zoned = try #require(BookingCapture.date(from: "2026-09-14T07:00:00Z"))
        #expect(zoned.timeIntervalSince1970 == 1_789_369_200)

        let local = try #require(BookingCapture.date(from: "2026-09-14T07:00:00"))
        #expect(calendar.component(.hour, from: local) == 7)
        #expect(calendar.component(.day, from: local) == 14)

        let minutes = try #require(BookingCapture.date(from: "2026-09-14T07:00"))
        #expect(calendar.component(.hour, from: minutes) == 7)

        let spaced = try #require(BookingCapture.date(from: "2026-09-14 07:00"))
        #expect(calendar.component(.hour, from: spaced) == 7)

        let dayOnly = try #require(BookingCapture.date(from: "2026-09-14"))
        #expect(calendar.component(.day, from: dayOnly) == 14)

        // Anything it can't read is dropped, never guessed.
        #expect(BookingCapture.date(from: "next Thursday") == nil)
        #expect(BookingCapture.date(from: "") == nil)
        #expect(BookingCapture.date(from: nil) == nil)
    }

    // MARK: - Merge

    @Test func mergeKeepsTheModelResultAndFillsGapsFromRegex() {
        var model = ParsedBooking()
        model.kind = .flight
        model.confirmationNumber = "MODEL1"
        model.seat = "3A"

        var regex = ParsedBooking()
        regex.kind = .hotel
        regex.confirmationNumber = "REGEX1"
        regex.originCode = "LAS"
        regex.amount = 99.0

        let merged = model.merging(regex)
        #expect(merged.kind == .flight)                 // model's kind wins
        #expect(merged.confirmationNumber == "MODEL1")  // model's value wins
        #expect(merged.seat == "3A")
        #expect(merged.originCode == "LAS")             // gap filled from regex
        #expect(merged.amount == 99.0)
    }

    @Test func mergeAdoptsAKindWhenTheModelHadNone() {
        var model = ParsedBooking()
        model.confirmationNumber = "ABC123"
        var regex = ParsedBooking()
        regex.kind = .carRental

        #expect(model.merging(regex).kind == .carRental)
    }

    // MARK: - Form routing

    @Test func bookingKindsMapToTheRightItineraryTypes() {
        #expect(ParsedBooking.Kind.flight.itemType == .flight)
        #expect(ParsedBooking.Kind.hotel.itemType == .hotel)
        #expect(ParsedBooking.Kind.carRental.itemType == .transport)
        #expect(ParsedBooking.Kind.other.itemType == .activity)
    }
}
