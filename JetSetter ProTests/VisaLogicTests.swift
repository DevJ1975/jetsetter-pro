// File: JetSetter ProTests/VisaLogicTests.swift
//
// Covers the destination matching shared by Visa Requirements, Travel
// Essentials and the Schengen counter, plus the visa nudge's lead time. Each
// defect test names the bug it guards against: these were all ways a real
// traveler would have been told something confidently wrong about a border.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct VisaLogicTests {

    // MARK: - US state codes vs ISO country codes

    /// Defect: "San Francisco, CA" resolved to Canada (an eTA nudge before a
    /// domestic trip), "Indianapolis, IN" to India (unsafe tap water, emergency
    /// number 112) and "Wilmington, DE" to Germany (Type F plugs), because a
    /// two-letter state code was read as an ISO country code.
    @Test(arguments: ["San Francisco, CA", "Indianapolis, IN", "Wilmington, DE"])
    func usCityAndStateNeverResolvesToTheCountrySharingItsCode(_ place: String) {
        let visa = VisaRequirements.find(query: place)
        #expect(visa == nil, "A US address needs no visa entry, got \(visa?.countryName ?? "nil")")

        let essentials = TravelEssentialsData.find(query: place)
        #expect(essentials?.id == "US")

        #expect(SchengenCalculator.placement(for: place) == .outside)
    }

    @Test func aStateCodeFollowedByAZipCodeIsStillAUSAddress() {
        #expect(USStateCodes.isUSCityState("Wilmington, DE 19801"))
        #expect(USStateCodes.isUSCityState("Austin, TX, USA"))
        #expect(TravelEssentialsData.find(query: "Indianapolis, IN 46204")?.id == "US")
    }

    @Test func aCountryNameStillResolvesAfterACity() {
        #expect(VisaRequirements.find(query: "Toronto, Canada")?.destination == "CA")
        #expect(TravelEssentialsData.find(query: "Toronto, Canada")?.id == "CA")
    }

    @Test func aStandAloneCodeOrACapitalisedCountrySlotIsStillACountry() {
        #expect(VisaRequirements.find(query: "CA")?.destination == "CA")
        #expect(VisaRequirements.find(query: "Lyon, FR")?.destination == "FR")
    }

    /// Defect: any two-letter word matched an ISO code, so "Hotel in Rome"
    /// resolved to India.
    @Test func anEnglishWordIsNotReadAsACountryCode() {
        #expect(VisaRequirements.find(query: "Hotel in Rome")?.destination != "IN")
        #expect(VisaRequirements.find(query: "Conference at the Hilton") == nil)
    }

    // MARK: - Schengen membership

    @Test func schengenHasAllTwentyNineMembersAndExcludesIrelandAndCyprus() {
        #expect(SchengenCalculator.memberCodes.count == 29)
        for code in ["BE", "BG", "RO", "HR", "PL", "SE", "IS", "NO", "LI", "CH"] {
            #expect(SchengenCalculator.isMember(code), "\(code) should be a member")
        }
        #expect(!SchengenCalculator.isMember("IE"))
        #expect(!SchengenCalculator.isMember("CY"))
        #expect(!SchengenCalculator.isMember("GB"))
    }

    @Test func tripsArePlacedByCountryCityOrAirport() {
        #expect(SchengenCalculator.placement(for: "Brussels, Belgium") == .schengen("BE"))
        #expect(SchengenCalculator.placement(for: "Kraków") == .schengen("PL"))
        #expect(SchengenCalculator.placement(for: "JFK → CDG") == .schengen("FR"))
        #expect(SchengenCalculator.placement(for: "Munich, DE") == .schengen("DE"))
        #expect(SchengenCalculator.placement(for: "Paris, TX") == .outside)
        #expect(SchengenCalculator.placement(for: "Dublin, Ireland") == .outside)
        #expect(SchengenCalculator.placement(for: "Atlanta, GA") == .outside)
        #expect(SchengenCalculator.placement(for: "Springfield") == .unknown)
    }

    // MARK: - Schengen day count

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func referenceDate() throws -> Date {
        try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
    }

    /// Defect: Belgium wasn't in the counter's 9-country list, so 60 days in
    /// Brussels counted as zero and the card showed "90 of 90 days".
    @Test func sixtyDaysInBrusselsLeavesThirtyOrFewerDays() throws {
        let now = try referenceDate()
        let start = try #require(utc.date(byAdding: .day, value: -59, to: now))
        let trip = Trip(name: "Brussels", destination: "Brussels, Belgium", startDate: start, endDate: now)

        let tally = SchengenCalculator.tally(trips: [trip], asOf: now, calendar: utc)

        #expect(tally.daysUsed == 60)
        #expect(tally.daysRemaining <= 30)
        #expect(tally.unplacedTripCount == 0)
    }

    @Test func overlappingTripRecordsCountEachDayOnce() throws {
        let now = try referenceDate()
        let start = try #require(utc.date(byAdding: .day, value: -9, to: now))
        let trips = [
            Trip(name: "Paris", destination: "Paris, France", startDate: start, endDate: now),
            Trip(name: "Paris again", destination: "CDG", startDate: start, endDate: now)
        ]

        #expect(SchengenCalculator.tally(trips: trips, asOf: now, calendar: utc).daysUsed == 10)
    }

    @Test func aRecentTripThatCannotBePlacedIsReportedAsUnplaced() throws {
        let now = try referenceDate()
        let start = try #require(utc.date(byAdding: .day, value: -20, to: now))
        let end = try #require(utc.date(byAdding: .day, value: -10, to: now))
        let trip = Trip(name: "Mystery", destination: "Springfield", startDate: start, endDate: end)

        let tally = SchengenCalculator.tally(trips: [trip], asOf: now, calendar: utc)

        #expect(tally.unplacedTripCount == 1)
        #expect(tally.daysRemaining == SchengenCalculator.allowanceDays)
    }

    @Test func anUnplacedTripOutsideTheWindowIsNotReported() throws {
        let now = try referenceDate()
        let start = try #require(utc.date(byAdding: .day, value: -300, to: now))
        let end = try #require(utc.date(byAdding: .day, value: -290, to: now))
        let trip = Trip(name: "Old", destination: "Springfield", startDate: start, endDate: end)

        #expect(SchengenCalculator.tally(trips: [trip], asOf: now, calendar: utc).unplacedTripCount == 0)
    }

    // MARK: - Visa nudge lead time

    @Test func leadTimeDependsOnTheKindOfPaperwork() {
        #expect(ProactiveSuggestions.visaNudgeLeadDays(for: .visaRequired) == 45)
        #expect(ProactiveSuggestions.visaNudgeLeadDays(for: .eVisa) == 21)
        #expect(ProactiveSuggestions.visaNudgeLeadDays(for: .eTA) == 10)
        #expect(ProactiveSuggestions.visaNudgeLeadDays(for: .visaOnArrival) == 7)
        #expect(ProactiveSuggestions.visaNudgeLeadDays(for: .visaFree) == nil)
    }

    private func makeTrip(to destination: String, inDays days: Int, from now: Date) throws -> Trip {
        let start = try #require(Calendar.current.date(byAdding: .day, value: days, to: now))
        let end = try #require(Calendar.current.date(byAdding: .day, value: 7, to: start))
        return Trip(name: destination, destination: destination, startDate: start, endDate: end)
    }

    /// Defect: the nudge opened only 0–7 days out, too late to get a
    /// consular visa.
    @Test func theVisaNudgeForAVisaRequiredDestinationOpensAtFortyFiveDays() throws {
        let now = Date()
        let engine = ProactiveSuggestions.shared

        let at45 = try makeTrip(to: "Beijing, China", inDays: 45, from: now)
        let at46 = try makeTrip(to: "Beijing, China", inDays: 46, from: now)

        let suggestion = engine.evaluateVisaCheck(trips: [at45], now: now)
        #expect(suggestion?.kind == .visaCheck)
        #expect(suggestion?.body.contains("US passport") == true)
        #expect(engine.evaluateVisaCheck(trips: [at46], now: now) == nil)
    }

    @Test func aDomesticTripSoonDoesNotHideAVisaTripLater() throws {
        let now = Date()
        let trips = [
            try makeTrip(to: "Atlanta, GA", inDays: 3, from: now),
            try makeTrip(to: "Beijing, China", inDays: 30, from: now)
        ]

        let suggestion = ProactiveSuggestions.shared.evaluateVisaCheck(trips: trips, now: now)
        #expect(suggestion?.title.contains("China") == true)
    }

    @Test func aDomesticTripNeverGetsAVisaNudge() throws {
        let now = Date()
        let trip = try makeTrip(to: "San Francisco, CA", inDays: 5, from: now)
        #expect(ProactiveSuggestions.shared.evaluateVisaCheck(trips: [trip], now: now) == nil)
    }
}
