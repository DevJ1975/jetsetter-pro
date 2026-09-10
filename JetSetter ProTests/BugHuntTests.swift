// File: JetSetter ProTests/BugHuntTests.swift
// Regression coverage for the end-to-end bug hunt: alphanumeric flight
// numbers, receipt totals with 4+ digits, airline-name fallbacks, currency
// words in Siri, stale departure briefings, WeatherKit symbol names, hotel
// hand-off paths, the router's pending actions and airport-local search days.
// Pure logic only — no network, no on-device model.

import Testing
import Foundation
import CoreLocation
@testable import JetSetter_Pro

@Suite(.serialized)
struct BugHuntTests {

    // MARK: - Flight numbers

    @Test func flightNumbersParseAlphanumericDesignators() {
        #expect(TravelStore.extractFlightNumber(from: "Flight — AA169 JFK → NRT") == "AA169")
        #expect(TravelStore.extractFlightNumber(from: "B6 715 to Boston") == "B6715")
        #expect(TravelStore.extractFlightNumber(from: "Frontier F9123") == "F9123")
        #expect(TravelStore.extractFlightNumber(from: "easyJet U2 4321") == "U24321")
        #expect(TravelStore.extractFlightNumber(from: "Gate B14 opens at noon") == nil)
        #expect(TravelStore.extractFlightNumber(from: "Booking 12345") == nil)
        #expect(TravelStore.extractFlightNumber(from: "Dinner at Nobu") == nil)
    }

    @Test func airlineDesignatorHandlesLettersAndAlphanumerics() {
        #expect(TravelStore.airlineDesignator(from: "DL2244") == "DL")
        #expect(TravelStore.airlineDesignator(from: "B6715") == "B6")
        #expect(TravelStore.airlineDesignator(from: "DAL123") == "DAL")
        #expect(TravelStore.airlineDesignator(from: "9W123") == "9W")
        #expect(TravelStore.airlineDesignator(from: "Flight") == "FLI")
        #expect(TravelStore.airlineDesignator(from: "1234") == "")
    }

    // MARK: - Receipts

    @Test func receiptTotalsKeepEveryDigit() {
        let large = VisionOCRService.shared.parseReceiptText("Hotel Danieli\nRoom 3 nights\nTOTAL 1234.56")
        #expect(large.extractedAmount == 1234.56)
        #expect(large.extractedMerchant == "Hotel Danieli")

        let grouped = VisionOCRService.shared.parseReceiptText("Restaurant\nAMOUNT DUE $1,250.00")
        #expect(grouped.extractedAmount == 1250.0)

        let yen = VisionOCRService.shared.parseReceiptText("Ichiran Ramen\nTOTAL ¥20,350")
        #expect(yen.extractedAmount == 20350)

        let european = VisionOCRService.shared.parseReceiptText("Trattoria\nTOTALE 1.234,56")
        #expect(european.extractedAmount == 1234.56)
    }

    @Test func receiptFallbackIgnoresDatesAndPhoneNumbers() {
        // No TOTAL line: whole numbers from the date and phone line must not win.
        let text = "Border Grill\n12/05/2024 14:32\nTel 310 555 0199\nLatte 4.50\nMuffin 3.25"
        let result = VisionOCRService.shared.parseReceiptText(text)
        #expect(result.extractedAmount == 4.50)
        #expect(result.extractedMerchant == "Border Grill")
    }

    // MARK: - Airline links

    @Test func airlineLinksNeverGuessFromAnUnknownName() {
        #expect(AirlineWebLinks.homepage(for: "Bangkok Airways") == nil)
        #expect(AirlineWebLinks.homepage(for: "Asiana Airlines") == nil)
        #expect(AirlineWebLinks.homepage(for: "Hainan Airlines") == nil)
        #expect(AirlineWebLinks.homepage(for: "BA")?.host == "www.britishairways.com")
        #expect(AirlineWebLinks.homepage(for: "BA 123")?.host == "www.britishairways.com")
    }

    // MARK: - Currency words

    @Test func currencyCodesAcceptCodesAndCommonWords() {
        #expect(CurrencyCodes.normalized("usd") == "USD")
        #expect(CurrencyCodes.normalized("Dollars") == "USD")
        #expect(CurrencyCodes.normalized("euros") == "EUR")
        #expect(CurrencyCodes.normalized("yen") == "JPY")
        #expect(CurrencyCodes.normalized("JPY") == "JPY")
        #expect(CurrencyCodes.normalized("xyz") == nil)
        #expect(CurrencyCodes.normalized("") == nil)
    }

    // MARK: - Departure briefing

    @Test func departureBriefingIsNotQuotedWhenStaleOrForAnotherFlight() {
        let saved = DepartureBriefing.cachedLive
        defer { DepartureBriefing.cachedLive = saved }

        let now = Date()
        DepartureBriefing.cachedLive = DepartureBriefing(
            leaveBy: "5:19 AM", driveMinutes: 34, tsaMinutes: 22, weatherLabel: "Clear",
            temperatureF: 74, flightNumber: "DL1423", originIATA: "LAS", computedAt: now
        )
        #expect(DepartureBriefing.current(for: "DL1423", now: now) != nil)
        #expect(DepartureBriefing.current(for: "dl1423", now: now) != nil)
        #expect(DepartureBriefing.current(for: "UA55", now: now) == nil)
        #expect(DepartureBriefing.current(for: nil, now: now) != nil)
        #expect(DepartureBriefing.current(for: "DL1423", now: now.addingTimeInterval(DepartureBriefing.maxAge + 1)) == nil)

        DepartureBriefing.cachedLive = nil
        #expect(DepartureBriefing.current() == nil)
    }

    // MARK: - Weather symbols

    @Test func weatherKitSymbolsOnlyGetFillWhenItExists() {
        #expect(WeatherService.filledSymbol("cloud.sun") == "cloud.sun.fill")
        #expect(WeatherService.filledSymbol("sun.max.fill") == "sun.max.fill")
        #expect(WeatherService.filledSymbol("wind") == "wind")
        #expect(WeatherService.filledSymbol("tornado") == "tornado")
    }

    // MARK: - Hotel hand-off

    @Test func hotelHandoffKeepsSlashedDestinationsInOnePathSegment() {
        var params = HotelSearchParams()
        params.destination = "Dallas/Fort Worth"
        let url = HotelBookingProvider.kayak.deepLinkURL(for: params)
        let segments = url?.pathComponents.filter { $0 != "/" } ?? []
        #expect(segments.count == 5)
        #expect(segments[1].contains("Dallas"))
        #expect(!segments.contains("Fort Worth"))
    }

    // MARK: - Router

    @Test @MainActor func routerPendingActionsSurviveUntilConsumed() {
        let router = AppRouter.shared
        let savedTab = router.selectedTab
        let savedAction = router.pendingAction
        defer {
            router.selectedTab = savedTab
            router.pendingAction = savedAction
        }
        router.pendingAction = nil
        #expect(router.pendingAction == nil)

        router.navigate(to: .checkIn)
        #expect(router.pendingAction == .checkIn)
        #expect(router.selectedTab == .home)

        // A stale consumer can't wipe a newer request.
        router.pendingAction = .generatePackingList(tripID: nil)
        router.consume(.checkIn)
        #expect(router.pendingAction == .generatePackingList(tripID: nil))

        router.consume(.generatePackingList(tripID: nil))
        #expect(router.pendingAction == nil)

        router.navigate(to: .disruption)
        #expect(router.pendingAction == .disruption)
        router.pendingAction = nil
    }

    // MARK: - Airport-local search day

    @Test func alternativeSearchUsesTheOriginAirportsCalendarDay() throws {
        // 06:30 UTC on Sep 10 is 23:30 on Sep 9 in Los Angeles.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-10T06:30:00Z"))
        let shifted = DisruptionResponseEngine.localCalendarDay(of: instant, at: "LAX")

        var la = Calendar(identifier: .gregorian)
        la.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let expected = la.dateComponents([.year, .month, .day], from: instant)
        let actual = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        #expect(actual.year == expected.year && actual.month == expected.month && actual.day == expected.day)

        // Unknown airport: the instant is returned untouched.
        #expect(DisruptionResponseEngine.localCalendarDay(of: instant, at: "ZZZ") == instant)
    }

    // MARK: - Local data store

    /// Uses the disruption store rather than the wallet: both go through the
    /// same `load()` helper, but the wallet is written by the demo-mode suite,
    /// and separate suites run in parallel.
    @Test func undecodableBlobIsMovedAsideInsteadOfOverwritten() async {
        let key = "supabase_local_disruption_events"
        let saved = UserDefaults.standard.data(forKey: key)
        let savedBackup = UserDefaults.standard.data(forKey: key + "_undecodable")
        defer {
            UserDefaults.standard.set(saved, forKey: key)
            UserDefaults.standard.set(savedBackup, forKey: key + "_undecodable")
        }

        let garbage = Data("not json at all".utf8)
        UserDefaults.standard.set(garbage, forKey: key)
        let events = await LocalDataService.shared.fetchDisruptionEvents()
        #expect(events.isEmpty)
        #expect(UserDefaults.standard.data(forKey: key + "_undecodable") == garbage)
        #expect(UserDefaults.standard.data(forKey: key) == nil)
    }
}
