// File: JetSetter ProTests/AirportTimeZoneTests.swift
//
// A flight time is a wall-clock time at an airport, not on the phone. These
// tests pin the three places that used to render or read flight times in the
// device zone: the shared `AppDateFormatters.airportTime` helper Siri speaks
// through, the boarding pass card, and booking capture.
//
// Every expectation is built from an explicit IANA zone and an explicit locale,
// so the result is the same on a CI runner in UTC and a laptop in Atlanta.
// Instants are mid-September 2026, when both US zones below are on daylight
// time: Las Vegas is UTC-7 and Atlanta UTC-4.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct AirportTimeZoneTests {

    // MARK: - Fixtures

    private let twelveHourLocale = Locale(identifier: "en_US")
    private let twentyFourHourLocale = Locale(identifier: "en_GB")

    /// The instant that reads `hour:minute` on `day` September 2026 in `zone`.
    private func instant(day: Int, hour: Int, minute: Int, in zone: String) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    /// DL1423 LAS → ATL, departing 09:05 in Las Vegas (16:05 UTC).
    private func departure() throws -> Date {
        try instant(day: 14, hour: 9, minute: 5, in: "America/Los_Angeles")
    }

    // MARK: - AppDateFormatters.airportTime

    @Test func theSameDepartureReadsThreeHoursLaterInAtlantaThanInLasVegas() throws {
        let date = try departure()
        #expect(AppDateFormatters.airportTime(date, iata: "LAS", style: .time, locale: twentyFourHourLocale) == "09:05")
        #expect(AppDateFormatters.airportTime(date, iata: "ATL", style: .time, locale: twentyFourHourLocale) == "12:05")

        let las = AppDateFormatters.airportTimeZone(for: "LAS").secondsFromGMT(for: date)
        let atl = AppDateFormatters.airportTimeZone(for: "ATL").secondsFromGMT(for: date)
        #expect(atl - las == 3 * 3_600)
    }

    @Test func airportCodesAreMatchedCaseInsensitively() throws {
        let date = try departure()
        #expect(AppDateFormatters.airportTime(date, iata: "las", style: .time, locale: twentyFourHourLocale) == "09:05")
    }

    @Test func aTwentyFourHourLocaleGetsTwentyFourHourTimeAndATwelveHourLocaleDoesNot() throws {
        let evening = try instant(day: 14, hour: 17, minute: 30, in: "America/Los_Angeles")

        #expect(AppDateFormatters.airportTime(evening, iata: "LAS", style: .time, locale: twentyFourHourLocale) == "17:30")

        let twelveHour = AppDateFormatters.airportTime(evening, iata: "LAS", style: .time, locale: twelveHourLocale)
        #expect(twelveHour.contains("5:30"))
        #expect(twelveHour.contains("PM"))
    }

    @Test func anUnknownOrMissingAirportFallsBackToTheDeviceZone() throws {
        let date = try departure()
        let device = AppDateFormatters.airportTime(date, in: .current, style: .dateTime, locale: twentyFourHourLocale)
        #expect(AppDateFormatters.airportTime(date, iata: "ZZZ", style: .dateTime, locale: twentyFourHourLocale) == device)
        #expect(AppDateFormatters.airportTime(date, iata: nil, style: .dateTime, locale: twentyFourHourLocale) == device)
        #expect(AppDateFormatters.airportTime(date, iata: "  ", style: .dateTime, locale: twentyFourHourLocale) == device)
        #expect(AppDateFormatters.airportTimeZone(for: "ZZZ") == TimeZone.current)
    }

    @Test func theDateIsTheAirportsCalendarDayNotThePhones() throws {
        // 20:30 on the 14th in Las Vegas is already 04:30 on the 15th in London.
        let lateDeparture = try instant(day: 14, hour: 20, minute: 30, in: "America/Los_Angeles")
        let las = AppDateFormatters.airportTime(lateDeparture, iata: "LAS", style: .weekdayDate, locale: twelveHourLocale)
        let lhr = AppDateFormatters.airportTime(lateDeparture, iata: "LHR", style: .weekdayDate, locale: twelveHourLocale)
        #expect(las.contains("Sep 14"))
        #expect(lhr.contains("Sep 15"))
    }

    // MARK: - Boarding pass

    private func boardingPass(date: Date, rawData: [String: String]) -> WalletItem {
        WalletItem(itemType: .boardingPass, title: "DL1423 LAS → ATL", date: date, rawData: rawData)
    }

    /// The defect this covers: boarding was computed as departure minus 30
    /// minutes, labelled as fact, and formatted with a forced "h:mm a" in the
    /// phone's zone, because the only zone source (`departure_timezone`) was
    /// never written by anything.
    @Test func theBoardingEstimateIsShownInTheDepartureAirportsZoneAndLocale() throws {
        let pass = boardingPass(date: try departure(), rawData: ["departure_airport": "LAS", "source": "demo"])
        #expect(BoardingPassCard.departureTimeZone(for: pass)?.identifier == "America/Los_Angeles")
        #expect(BoardingPassCard.boardingTimeString(for: pass, locale: twentyFourHourLocale) == "08:35")
    }

    @Test func aPassThatCarriesItsOwnZoneWinsOverTheAirportTable() throws {
        let pass = boardingPass(date: try departure(), rawData: [
            "departure_airport": "LAS",
            "departure_timezone": "America/New_York"
        ])
        #expect(BoardingPassCard.boardingTimeString(for: pass, locale: twentyFourHourLocale) == "11:35")
    }

    @Test func aScannedBarcodeOrImportedPkpassHasNoBoardingTimeToShow() throws {
        // A BCBP barcode carries only the day; a .pkpass date is its
        // relevantDate. Counting 30 minutes back from either invents a time.
        let scanned = boardingPass(date: try departure(), rawData: ["departure_airport": "LAS", "source": "bcbp_scan"])
        #expect(BoardingPassCard.estimatedBoardingTime(for: scanned) == nil)
        #expect(BoardingPassCard.boardingTimeString(for: scanned) == "—")

        let imported = boardingPass(date: try departure(), rawData: ["pkpass_data": "AAAA"])
        #expect(BoardingPassCard.estimatedBoardingTime(for: imported) == nil)
        #expect(BoardingPassCard.boardingTimeString(for: imported) == "—")
    }

    @Test func withoutAKnownAirportTheBoardingTimeNamesThePhonesZone() throws {
        let date = try departure()
        let pass = boardingPass(date: date, rawData: ["departure_airport": "—"])
        let shown = BoardingPassCard.boardingTimeString(for: pass, locale: twentyFourHourLocale)
        let expected = AppDateFormatters.airportTime(date.addingTimeInterval(-30 * 60), in: .current, style: .time, locale: twentyFourHourLocale)
        #expect(shown.hasPrefix(expected))
        if let abbreviation = TimeZone.current.abbreviation(for: date.addingTimeInterval(-30 * 60)) {
            #expect(shown.hasSuffix(abbreviation))
        }
    }

    @Test func thePassDateIsTheDepartureAirportsDay() throws {
        let lateDeparture = try instant(day: 14, hour: 22, minute: 45, in: "America/Los_Angeles")
        let pass = boardingPass(date: lateDeparture, rawData: ["departure_airport": "LAS"])
        #expect(BoardingPassCard.flightDateString(for: pass, locale: twelveHourLocale).contains("Sep 14"))
    }

    // MARK: - Booking capture

    /// The defect this covers: a captured "DL1423 LAS→ATL departs 9:05 AM" was
    /// read in the phone's zone, so on a phone set to Atlanta it was saved as
    /// 9:05 Eastern, three hours before the real departure.
    @Test func aCapturedDepartureIsReadAtTheOriginAndArrivalAtTheDestination() throws {
        let expectedDeparture = try departure()
        let expectedArrival = try instant(day: 14, hour: 16, minute: 20, in: "America/New_York")
        let times = BookingCapture.bookingTimes(
            start: "2026-09-14T09:05:00",
            end: "2026-09-14T16:20:00",
            isFlight: true,
            originCode: "LAS",
            destinationCode: "ATL"
        )
        #expect(times.start == expectedDeparture)
        #expect(times.end == expectedArrival)
    }

    @Test func aTimeThatAlreadyCarriesAZoneIsNotMoved() throws {
        let expectedDeparture = try departure()
        let times = BookingCapture.bookingTimes(
            start: "2026-09-14T16:05:00Z", end: nil,
            isFlight: true, originCode: "ATL", destinationCode: nil
        )
        #expect(times.start == expectedDeparture)
        #expect(times.end == nil)
    }

    @Test func unknownAirportsHotelsAndBareDatesKeepTheDeviceZone() {
        let raw = "2026-09-14T09:05:00"
        let deviceReading = BookingCapture.date(from: raw)

        let unknownAirport = BookingCapture.bookingTimes(start: raw, end: nil, isFlight: true, originCode: "ZZZ", destinationCode: nil)
        #expect(unknownAirport.start == deviceReading)

        let noAirport = BookingCapture.bookingTimes(start: raw, end: nil, isFlight: true, originCode: nil, destinationCode: nil)
        #expect(noAirport.start == deviceReading)

        let hotel = BookingCapture.bookingTimes(start: raw, end: nil, isFlight: false, originCode: "LAS", destinationCode: nil)
        #expect(hotel.start == deviceReading)

        // A day with no clock time stays on the phone's calendar, so the form's
        // date picker can't show it as the day before.
        let dayOnly = BookingCapture.bookingTimes(start: "2026-09-14", end: nil, isFlight: true, originCode: "ATL", destinationCode: nil)
        #expect(dayOnly.start == BookingCapture.date(from: "2026-09-14"))
    }

    @Test func dateParsingHonoursAnExplicitZone() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let parsed = try #require(BookingCapture.date(from: "2026-09-14T09:05", in: tokyo))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        #expect(calendar.component(.hour, from: parsed) == 9)
        #expect(calendar.component(.minute, from: parsed) == 5)
    }
}
