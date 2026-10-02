// File: JetSetter ProTests/FlightFactsTests.swift
//
// Covers how a flight's gate and terminal are resolved (the structured booking
// field before the free-text notes) and how Home renders the departure time
// (in the origin airport's zone, not the phone's).

import Testing
import Foundation
@testable import JetSetter_Pro

@Suite
@MainActor
struct FlightFactsTests {

    // MARK: - Gate and terminal

    /// Defect: Add Itinerary saves a typed gate to `flightDetails.gate`, but
    /// Home, the departure board and More only read "Gate B22" out of `notes`,
    /// so the gate the traveler typed never appeared.
    @Test func theTypedGateWinsOverTheNotes() {
        let item = ItineraryItem(
            title: "Delta DL1423", type: .flight, startDate: Date(),
            notes: "Gate B22 · Terminal 1",
            flightDetails: FlightBookingDetails(terminal: "S", gate: "C7")
        )
        #expect(item.resolvedGate == "C7")
        #expect(item.resolvedTerminal == "S")
    }

    @Test func theNotesAreTheFallbackWhenNothingWasTyped() {
        let item = ItineraryItem(
            title: "Delta DL1423", type: .flight, startDate: Date(),
            notes: "Gate B22 · Terminal 1 · Seat 3A",
            flightDetails: FlightBookingDetails(seat: "3A", gate: "   ")
        )
        #expect(item.resolvedGate == "B22")
        #expect(item.resolvedTerminal == "1")
    }

    @Test func anUnknownGateIsNilRatherThanAPlaceholder() {
        let bare = ItineraryItem(title: "Delta DL1423", type: .flight, startDate: Date())
        #expect(bare.resolvedGate == nil)
        #expect(bare.resolvedTerminal == nil)

        let placeholder = ItineraryItem(
            title: "Delta DL1423", type: .flight, startDate: Date(), notes: "Gate TBD"
        )
        #expect(placeholder.resolvedGate == nil)
    }

    // MARK: - Home "Departs"

    /// Defect: Home formatted the departure in the phone's zone with a forced
    /// 12-hour clock, so a 08:00 LAX departure read "11:00 AM" on a phone
    /// still set to New York.
    @Test func homeShowsTheDepartureInTheOriginAirportsZone() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-03-15T15:00:00Z"))
        let britishEnglish = Locale(identifier: "en_GB")
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))

        // Phone in the same zone as the airport: just the 24-hour local time.
        #expect(HomeViewModel.departureTimeText(
            date, originIATA: "LAX", locale: britishEnglish, deviceZone: losAngeles) == "08:00")
        // Phone elsewhere: the airport's wall clock, labelled with its zone.
        #expect(HomeViewModel.departureTimeText(
            date, originIATA: "LAX", locale: britishEnglish, deviceZone: newYork) == "08:00 PDT")
        // Unknown airport: fall back to the phone's zone, never crash.
        #expect(HomeViewModel.departureTimeText(
            date, originIATA: "XYZ", locale: britishEnglish, deviceZone: newYork) == "11:00")
    }

    @Test func homeShowsTheDepartureDateAtTheOriginAirport() throws {
        // 23:30 on the 14th in Los Angeles is already the 15th in New York.
        let date = try #require(ISO8601DateFormatter().date(from: "2026-03-15T06:30:00Z"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let text = HomeViewModel.departureDateText(
            date, originIATA: "LAX", locale: Locale(identifier: "en_US"), deviceZone: newYork)
        #expect(text.contains("14"))
        #expect(!text.contains("15"))
    }
}
