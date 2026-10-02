// File: JetSetter ProTests/TripDayAccessibilityTests.swift
//
// What VoiceOver hears on the trip-day screens, and the contrast floor for
// white text on the theme's fill colours.
//
// Times are built from an explicit IANA zone and locale, so the expectations
// hold on a CI runner in UTC and on a laptop in Atlanta. The fixture is the
// demo flight: DL1423 Las Vegas → Atlanta, 09:05 in Las Vegas on 14 Sep 2026
// (UTC-7 on daylight time).

import Testing
import Foundation
import UIKit
@testable import JetSetter_Pro

@MainActor
@Suite struct TripDayAccessibilityTests {

    // MARK: - Fixtures

    private let twelveHourLocale = Locale(identifier: "en_US")

    private func lasVegasDeparture() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9, minute: 5)))
    }

    private func pass(_ extra: [String: String] = [:], date: Date) -> WalletItem {
        var raw: [String: String] = [
            "airline": "Delta",
            "flight_number": "DL1423",
            "iata_code": "DL",
            "departure_airport": "LAS",
            "arrival_airport": "ATL",
            "gate": "C22",
            "seat_number": "3A",
            "source": "demo"
        ]
        raw.merge(extra) { _, new in new }
        return WalletItem(itemType: .boardingPass, title: "DL1423 LAS → ATL", date: date, rawData: raw)
    }

    private func lasVegasTime(_ date: Date) throws -> String {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return AppDateFormatters.airportTime(date, in: zone, style: .time, locale: twelveHourLocale)
    }

    // MARK: - Boarding pass summary

    /// The defect this covers: VoiceOver walked the pass a fragment at a time
    /// ("L A S", "airplane", "A T L", "GATE", "C22"), about a dozen swipes
    /// before a traveler at the gate heard their seat.
    @Test func theBoardingPassReadsAsOneSentenceWithTheTimeAtTheDepartureAirport() throws {
        let departure = try lasVegasDeparture()
        let summary = BoardingPassCard.accessibilitySummary(for: pass(date: departure), locale: twelveHourLocale)

        let departs = try lasVegasTime(departure)
        let boards = try lasVegasTime(departure.addingTimeInterval(-30 * 60))
        #expect(departs.hasPrefix("9:05"))
        #expect(summary == "Delta flight 1423, Las Vegas to Atlanta, departs \(departs), gate C22, seat 3A, "
                + "boarding about \(boards), estimated")
    }

    @Test func anUnknownGateOrSeatIsSaidAsNotAssignedYetNeverGuessed() throws {
        let summary = BoardingPassCard.accessibilitySummary(
            for: pass(["gate": "—", "seat_number": ""], date: try lasVegasDeparture()),
            locale: twelveHourLocale
        )
        #expect(summary.contains("gate not assigned yet, seat not assigned yet"))
        #expect(!summary.contains("—"))
    }

    @Test func aSeatChosenAtCheckInOverridesTheSeatOnThePass() throws {
        let summary = BoardingPassCard.accessibilitySummary(
            for: pass(date: try lasVegasDeparture()), seatOverride: "14C", locale: twelveHourLocale
        )
        #expect(summary.contains("seat 14C"))
        #expect(!summary.contains("seat 3A"))
    }

    /// A scanned barcode carries only the flight's day, so the summary says the
    /// day and doesn't invent a departure or boarding time.
    @Test func aScannedPassSpeaksItsDayAndNoInventedTime() throws {
        let scanned = pass(["source": "bcbp_scan"], date: try lasVegasDeparture())
        let summary = BoardingPassCard.accessibilitySummary(for: scanned, locale: twelveHourLocale)
        let day = BoardingPassCard.flightDateString(for: scanned, locale: twelveHourLocale)
        #expect(summary.contains("departs \(day)"))
        #expect(!summary.contains("boarding about"))
    }

    @Test func withoutAnAirlineNameTheCarrierIsNamedFromItsCode() throws {
        let unnamed = pass(["airline": ""], date: try lasVegasDeparture())
        let summary = BoardingPassCard.accessibilitySummary(for: unnamed, locale: twelveHourLocale)
        #expect(summary.hasPrefix("Delta Air Lines flight 1423, "))
    }

    @Test func terminalAndBoardingGroupAreReadWhenThePassHasThem() throws {
        let full = pass(["terminal": "1", "boarding_group": "2"], date: try lasVegasDeparture())
        let summary = BoardingPassCard.accessibilitySummary(for: full, locale: twelveHourLocale)
        #expect(summary.contains("seat 3A, terminal 1, boarding group 2"))
    }

    // MARK: - Spoken routes

    @Test func airportCodesAreSpokenAsCities() {
        #expect(TripSpeech.spokenRoute(["LAS", "ATL"]) == "Las Vegas to Atlanta")
        #expect(TripSpeech.spokenRoute(["las", "DEN", "ATL"]) == "Las Vegas to Denver to Atlanta")
    }

    /// An unknown code is spelled out rather than guessed at, and a missing
    /// one says so instead of reading "dash".
    @Test func unknownAndMissingAirportsAreNeverGuessed() {
        #expect(TripSpeech.spokenAirport("XQZ") == "X Q Z")
        #expect(TripSpeech.spokenAirport("—") == "unknown airport")
        #expect(TripSpeech.spokenAirport(nil) == "unknown airport")
        #expect(TripSpeech.codes(fromDisplayRoute: "LAS → ATL") == ["LAS", "ATL"])
    }

    // MARK: - Departures board

    /// The defect this covers: each split-flap tile was its own element, so
    /// VoiceOver read single letters, and mid-flip it read the wrong ones.
    @Test func aDeparturesRowIsOneSentenceBuiltFromItsValues() {
        let row = FlightBoardRow(
            flightNumber: "DL1423", destinationIATA: "ATL", destinationName: "ATL",
            scheduledTime: "09:05", gate: "C22", terminal: "1",
            status: .scheduled, isUserFlight: true
        )
        #expect(FlightBoardView.accessibilityText(for: row)
                == "Your flight DL1423 to Atlanta, departs 09:05, gate C22, terminal 1, scheduled")

        let unknownGate = FlightBoardRow(
            flightNumber: "UA837", destinationIATA: "LHR", destinationName: "LHR",
            scheduledTime: "18:25", gate: "—", terminal: "",
            status: .boarding
        )
        #expect(FlightBoardView.accessibilityText(for: unknownGate)
                == "Flight UA837 to London, departs 18:25, gate not assigned yet, boarding")
    }

    // MARK: - Contrast

    /// WCAG 2.x contrast ratio between two opaque colours.
    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            func linear(_ c: CGFloat) -> Double {
                let v = Double(c)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The defect this covers: white button text sat on the dark-mode accent
    /// #3B9EF0 at 2.86:1, below WCAG AA's 4.5:1 for normal text.
    @Test func everyFillBehindWhiteTextMeetsWCAGAA() {
        for hex in JetsetterTheme.Colors.FillHex.all {
            let ratio = contrast(.white, UIColor(hex: hex))
            #expect(ratio >= 4.5, "white on \(hex) is \(ratio):1")
        }
        #expect(contrast(.white, UIColor(hex: "#3B9EF0")) < 3.0)
        #expect(abs(contrast(.white, UIColor(hex: JetsetterTheme.Colors.FillHex.executiveAccentDark)) - 4.87) < 0.01)
    }
}
