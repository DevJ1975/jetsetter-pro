// File: JetSetter ProTests/WidgetTimelineTests.swift
//
// Covers the time arithmetic behind the widgets: when a widget's timeline
// needs entries for a flight, which flight is "next", and how countdowns, day
// offsets and home-versus-destination clocks read across time zones. Plus the
// recovery of an exact leave-by instant from the briefing's formatted time.
//
// Every expectation is built from explicit IANA zones and locales, so results
// match on a CI runner in UTC and a laptop in Atlanta. Instants are September
// 2026: Las Vegas UTC-7, Atlanta UTC-4, Auckland UTC+12 (before NZ daylight
// time), Sydney UTC+10 (before Australian daylight time), Honolulu UTC-10.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct WidgetTimelineTests {

    // MARK: - Fixtures

    private let lasVegas = "America/Los_Angeles"
    private let atlanta = "America/New_York"

    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    private func instant(day: Int, hour: Int, minute: Int, in zoneID: String) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try zone(zoneID)
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    /// DL1423 LAS → ATL: 09:05 in Las Vegas on 14 September, landing 16:12 in Atlanta.
    private func scheduledDeparture() throws -> Date { try instant(day: 14, hour: 9, minute: 5, in: lasVegas) }
    private func scheduledArrival() throws -> Date { try instant(day: 14, hour: 16, minute: 12, in: atlanta) }

    private func sampleFlight() throws -> WidgetSnapshot.FlightLeg {
        let departure = try scheduledDeparture()
        let landing = try scheduledArrival()
        return WidgetSnapshot.FlightLeg(
            id: UUID(), flightNumber: "DL1423", airline: "Delta Air Lines",
            originCode: "LAS", originCity: "Las Vegas", destinationCode: "ATL", destinationCity: "Atlanta",
            departure: departure, arrival: landing,
            originTimeZoneID: lasVegas, destinationTimeZoneID: atlanta,
            gate: "C22", terminal: "1", seat: "3A", walletPassID: nil,
            checkInOpensAt: departure.addingTimeInterval(-24 * 3_600),
            boardingEstimate: departure.addingTimeInterval(-30 * 60))
    }

    /// Leave at 07:05, from a live reading taken at 06:20 that's quoted for six hours.
    private func sampleLeaveBy(for flight: WidgetSnapshot.FlightLeg) -> WidgetSnapshot.LeaveBy {
        let computedAt = flight.departure.addingTimeInterval(-(2 * 3_600 + 45 * 60))
        return WidgetSnapshot.LeaveBy(flightID: flight.id, leaveAt: flight.departure.addingTimeInterval(-2 * 3_600),
                                      usesLiveTraffic: true, computedAt: computedAt,
                                      expiresAt: computedAt.addingTimeInterval(6 * 3_600))
    }

    // MARK: - Timeline moments

    @Test func aFlightChangesAtCheckInLeaveByBoardingDepartureAndArrival() throws {
        let flight = try sampleFlight()
        let leaveBy = sampleLeaveBy(for: flight)
        let moments = WidgetTimelinePlanner.moments(for: flight, leaveBy: leaveBy)
        let d = flight.departure
        let landing = try scheduledArrival()

        #expect(moments.map(\.kind) == [
            .checkInOpens, .countdownStarts, .leaveByBecomesEstimate, .leaveBy, .boarding, .departure, .arrival
        ])
        #expect(moments.map(\.date) == [
            d.addingTimeInterval(-24 * 3_600),
            d.addingTimeInterval(-12 * 3_600),
            d.addingTimeInterval(-(2 * 3_600 + 15 * 60)),
            d.addingTimeInterval(-2 * 3_600),
            d.addingTimeInterval(-30 * 60),
            d,
            landing
        ])
    }

    /// A leave-by for a different flight adds nothing to this one.
    @Test func anotherFlightsLeaveByIsIgnored() throws {
        let flight = try sampleFlight()
        var other = try sampleFlight()
        other.id = UUID()
        let moments = WidgetTimelinePlanner.moments(for: flight, leaveBy: sampleLeaveBy(for: other))
        #expect(!moments.contains(where: { $0.kind == .leaveBy }))
    }

    @Test func entryDatesStartNowAndCoverEveryMomentInTheHorizon() throws {
        let flight = try sampleFlight()
        let arrival = try scheduledArrival()
        let tripEnd = try instant(day: 15, hour: 10, minute: 0, in: atlanta)
        let hotel = WidgetSnapshot.DayItem(id: UUID(), kind: .hotel, title: "Hotel",
                                           start: arrival.addingTimeInterval(90 * 60), timeZoneID: atlanta)
        let trip = WidgetSnapshot.TripSummary(
            id: UUID(), name: "Atlanta Board Meeting", destination: "Atlanta, GA",
            startDate: flight.departure.addingTimeInterval(-3_600), endDate: tripEnd,
            destinationCode: "ATL", destinationTimeZoneID: atlanta,
            flights: [flight], items: [hotel], weather: nil)
        let snapshot = WidgetSnapshot(schemaVersion: 2, generatedAt: flight.departure, homeTimeZoneID: lasVegas,
                                      trips: [trip], leaveBy: sampleLeaveBy(for: flight))
        let now = flight.departure.addingTimeInterval(-20 * 3_600)   // 13 Sep, 13:05 in Las Vegas
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try zone(lasVegas)

        let dates = WidgetTimelinePlanner.entryDates(for: snapshot, tripID: nil, now: now, calendar: calendar)

        #expect(dates.first == now)
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(dates.allSatisfy({ $0 >= now && $0 <= now.addingTimeInterval(WidgetTimelinePlanner.horizon) }))

        // Check-in opened before now, so it's not an entry; everything later is.
        #expect(!dates.contains(flight.departure.addingTimeInterval(-24 * 3_600)))
        for moment in WidgetTimelinePlanner.moments(for: flight, leaveBy: snapshot.leaveBy) where moment.date > now {
            #expect(dates.contains(moment.date), "missing \(moment.kind)")
        }
        #expect(dates.contains(trip.startDate))
        #expect(dates.contains(tripEnd))
        #expect(dates.contains(hotel.start))

        // Midnight in Las Vegas (the phone and home) and in Atlanta (the
        // destination clock's day badge).
        let midnights = try [
            instant(day: 14, hour: 0, minute: 0, in: lasVegas),
            instant(day: 15, hour: 0, minute: 0, in: lasVegas),
            instant(day: 14, hour: 0, minute: 0, in: atlanta),
            instant(day: 15, hour: 0, minute: 0, in: atlanta)
        ]
        for midnight in midnights {
            #expect(dates.contains(midnight))
        }
    }

    @Test func withNoTripsATimelineIsJustNow() throws {
        let now = try scheduledDeparture()
        let calendar = Calendar(identifier: .gregorian)
        #expect(WidgetTimelinePlanner.entryDates(for: nil, tripID: nil, now: now, calendar: calendar) == [now])
        #expect(WidgetTimelinePlanner.entryDates(for: .empty(generatedAt: now), tripID: nil, now: now,
                                                 calendar: calendar) == [now])
    }

    /// Without live status the widget can't say a flight is in the air, so a
    /// flight with no scheduled arrival gives way to the next one at departure.
    @Test func aFlightWithoutAnArrivalTimeDropsOffAtDeparture() throws {
        var first = try sampleFlight()
        first.arrival = nil
        var second = try sampleFlight()
        second.id = UUID()
        second.departure = try instant(day: 14, hour: 18, minute: 0, in: lasVegas)
        second.arrival = nil

        let before = try instant(day: 14, hour: 8, minute: 0, in: lasVegas)
        let after = try instant(day: 14, hour: 9, minute: 30, in: lasVegas)
        #expect(WidgetTimelinePlanner.currentFlight(in: [second, first], at: before)?.id == first.id)
        #expect(WidgetTimelinePlanner.currentFlight(in: [second, first], at: after)?.id == second.id)

        // With an arrival, it stays the current flight until it lands.
        let flight = try sampleFlight()
        #expect(WidgetTimelinePlanner.currentFlight(in: [flight], at: after)?.id == flight.id)
    }

    @Test func plainTextCountdownsRefreshMoreOftenAsDepartureNears() throws {
        let target = try scheduledDeparture()
        let dates = WidgetTimelinePlanner.countdownRefreshDates(until: target, after: target.addingTimeInterval(-13 * 3_600))

        #expect(dates.count == 24 + 24 + 18)
        #expect(dates.first == target.addingTimeInterval(-12 * 3_600))
        #expect(dates.last == target.addingTimeInterval(-5 * 60))
        let lastTwoHours = dates.filter { $0 >= target.addingTimeInterval(-2 * 3_600) }
        let gaps = zip(lastTwoHours, lastTwoHours.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect(gaps.allSatisfy({ $0 == 5 * 60 }))
    }

    // MARK: - Day offsets

    @Test func aRedEyeFromLasVegasLandsTheNextDayInAtlanta() throws {
        let departure = try instant(day: 14, hour: 23, minute: 30, in: lasVegas)
        let arrival = try instant(day: 15, hour: 6, minute: 45, in: atlanta)
        let days = try WidgetClock.dayOffset(from: departure, in: zone(lasVegas), to: arrival, in: zone(atlanta))
        #expect(days == 1)
        #expect(WidgetClock.dayOffsetLabel(days) == "+1")
        #expect(WidgetClock.spokenDayOffset(days) == "the next day")
    }

    @Test func westboundAcrossTheDateLineCanLandTwoDaysLater() throws {
        let departure = try instant(day: 14, hour: 22, minute: 30, in: lasVegas)          // LAX, Monday night
        let arrival = try instant(day: 16, hour: 6, minute: 30, in: "Australia/Sydney")   // Wednesday morning
        let days = try WidgetClock.dayOffset(from: departure, in: zone(lasVegas), to: arrival, in: zone("Australia/Sydney"))
        #expect(days == 2)
        #expect(WidgetClock.dayOffsetLabel(days) == "+2")
    }

    @Test func eastboundAcrossTheDateLineCanLandTheDayBefore() throws {
        let departure = try instant(day: 15, hour: 0, minute: 30, in: "Pacific/Auckland")
        let arrival = try instant(day: 14, hour: 11, minute: 15, in: "Pacific/Honolulu")
        let days = try WidgetClock.dayOffset(from: departure, in: zone("Pacific/Auckland"), to: arrival, in: zone("Pacific/Honolulu"))
        #expect(days == -1)
        #expect(WidgetClock.dayOffsetLabel(days) == "\u{2212}1")
        #expect(WidgetClock.spokenDayOffset(days) == "the previous day")
    }

    @Test func aSameDayArrivalHasNoBadge() throws {
        let days = try WidgetClock.dayOffset(from: scheduledDeparture(), in: zone(lasVegas), to: scheduledArrival(), in: zone(atlanta))
        #expect(days == 0)
        #expect(WidgetClock.dayOffsetLabel(days) == nil)
    }

    // MARK: - Countdowns

    /// A countdown is between two instants, so it reads the same whether the
    /// traveler's phone is on Atlanta or Las Vegas time.
    @Test func aCountdownIsTheSameWhicheverZoneTheTravelerIsIn() throws {
        let nowInAtlanta = try instant(day: 14, hour: 11, minute: 0, in: atlanta)   // 08:00 in Las Vegas
        let departure = try scheduledDeparture()                    // 09:05 in Las Vegas
        #expect(WidgetClock.compactCountdown(from: nowInAtlanta, to: departure) == "1h 5m")
        #expect(WidgetClock.spokenCountdown(from: nowInAtlanta, to: departure) == "1 hour 5 minutes")
    }

    @Test func countdownsFloorToWholeUnitsLikeHome() throws {
        let target = try scheduledDeparture()
        #expect(WidgetClock.compactCountdown(from: target.addingTimeInterval(-2 * 3_600), to: target) == "2h 0m")
        #expect(WidgetClock.spokenCountdown(from: target.addingTimeInterval(-2 * 3_600), to: target) == "2 hours")
        #expect(WidgetClock.compactCountdown(from: target.addingTimeInterval(-(3 * 86_400 + 2.5 * 3_600)), to: target) == "3d 2h")
        #expect(WidgetClock.spokenCountdown(from: target.addingTimeInterval(-(86_400 + 60)), to: target) == "1 day")
        #expect(WidgetClock.compactCountdown(from: target.addingTimeInterval(-59), to: target) == "<1m")
        #expect(WidgetClock.spokenCountdown(from: target.addingTimeInterval(-59), to: target) == "less than a minute")
        #expect(WidgetClock.compactCountdown(from: target, to: target) == nil)
        #expect(WidgetClock.compactCountdown(from: target.addingTimeInterval(60), to: target) == nil)
    }

    @Test func gaugeFractionsClampToTheirWindow() throws {
        let target = try scheduledDeparture()
        let window: TimeInterval = 3 * 3_600
        #expect(WidgetClock.remainingFraction(at: target.addingTimeInterval(-5 * 3_600), until: target, window: window) == 1)
        #expect(WidgetClock.remainingFraction(at: target.addingTimeInterval(-90 * 60), until: target, window: window) == 0.5)
        #expect(WidgetClock.remainingFraction(at: target.addingTimeInterval(60), until: target, window: window) == 0)
    }

    // MARK: - Home and destination clocks

    @Test func homeVersusDestinationOffsetsIncludeHalfHourZones() throws {
        let date = try scheduledDeparture()
        let vegas = try zone(lasVegas)
        let georgia = try zone(atlanta)
        let kolkata = try zone("Asia/Kolkata")
        #expect(WidgetClock.offsetLabel(home: vegas, destination: georgia, at: date) == "+3h")
        #expect(WidgetClock.offsetLabel(home: georgia, destination: vegas, at: date) == "\u{2212}3h")
        #expect(WidgetClock.offsetLabel(home: vegas, destination: kolkata, at: date) == "+12h 30m")
        #expect(WidgetClock.offsetLabel(home: georgia, destination: georgia, at: date) == "Same time")
    }

    @Test func theDestinationCanAlreadyBeOnTomorrow() throws {
        let evening = try instant(day: 14, hour: 20, minute: 0, in: lasVegas)   // 12:00 on the 15th in Tokyo
        let home = try zone(lasVegas)
        let tokyo = try zone("Asia/Tokyo")
        let georgia = try zone(atlanta)
        #expect(WidgetClock.dayDifference(at: evening, home: home, destination: tokyo) == 1)
        #expect(WidgetClock.dayDifference(at: evening, home: home, destination: georgia) == 0)
        #expect(WidgetClock.dayDifference(at: evening, home: tokyo, destination: home) == -1)
    }

    // MARK: - Airport-local times

    /// The widget extension can't link `AppDateFormatters`, so it carries its
    /// own copy of the airport-time format. This keeps the two identical.
    @Test func widgetTimesMatchTheAppsAirportFormatter() throws {
        let date = try scheduledDeparture()
        for zoneID in [lasVegas, atlanta, "Asia/Tokyo", "Asia/Kolkata"] {
            for localeID in ["en_US", "en_GB", "de_DE"] {
                let tz = try zone(zoneID)
                let locale = Locale(identifier: localeID)
                #expect(WidgetClock.time(date, in: tz, locale: locale)
                        == AppDateFormatters.airportTime(date, in: tz, style: .time, locale: locale))
            }
        }
    }

    @Test func aZoneIsOnlyNamedWhenItDiffersFromThePhones() throws {
        let date = try scheduledDeparture()
        let atlantaZone = try zone(atlanta)
        let vegas = try zone(lasVegas)
        #expect(WidgetClock.zoneLabel(atlantaZone, differingFrom: vegas, at: date)
                == atlantaZone.abbreviation(for: date))
        #expect(WidgetClock.zoneLabel(atlantaZone, differingFrom: atlantaZone, at: date) == nil)
    }

    // MARK: - Leave-by instant

    private func leaveByFormatter(_ localeID: String, _ zoneID: String) throws -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeID)
        formatter.timeZone = try zone(zoneID)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    /// The briefing's "6:20 AM" carries no day. Taking the next 6:20 after
    /// the briefing was computed would put a leave-by for a flight three days
    /// out on tomorrow morning; the day has to come from the flight.
    @Test func aLeaveTimeLandsOnTheFlightsDayNotTomorrow() throws {
        let departure = try instant(day: 17, hour: 9, minute: 5, in: lasVegas)
        let expected = try instant(day: 17, hour: 6, minute: 20, in: lasVegas)
        let vegas = try zone(lasVegas)
        for localeID in ["en_US", "en_GB"] {
            let text = try leaveByFormatter(localeID, lasVegas).string(from: expected)
            let recovered = WidgetBridge.leaveInstant(fromLeaveBy: text, before: departure,
                                                      locale: Locale(identifier: localeID), timeZone: vegas)
            #expect(recovered == expected)
        }
    }

    @Test func aLeaveTimeBeforeMidnightBelongsToTheEveningBefore() throws {
        let departure = try instant(day: 15, hour: 0, minute: 40, in: lasVegas)
        let expected = try instant(day: 14, hour: 22, minute: 50, in: lasVegas)
        let text = try leaveByFormatter("en_US", lasVegas).string(from: expected)
        let vegas = try zone(lasVegas)
        #expect(WidgetBridge.leaveInstant(fromLeaveBy: text, before: departure, locale: Locale(identifier: "en_US"),
                                          timeZone: vegas) == expected)
    }

    @Test func aPassedWindowIsNeverTurnedIntoATime() throws {
        let departure = try scheduledDeparture()
        let vegas = try zone(lasVegas)
        #expect(WidgetBridge.leaveInstant(fromLeaveBy: "now (window passed)", before: departure,
                                          locale: Locale(identifier: "en_US"), timeZone: vegas) == nil)
    }

    /// End to end with the formatter the optimizer itself uses (the phone's
    /// locale and zone), so this holds on any CI runner.
    @Test func aLiveBriefingBecomesTheLeaveByForItsFlightOnly() throws {
        let flight = try sampleFlight()
        let expected = flight.departure.addingTimeInterval(-(2 * 3_600 + 45 * 60))
        let optimizerFormatter = DateFormatter()
        optimizerFormatter.dateStyle = .none
        optimizerFormatter.timeStyle = .short
        let computedAt = expected.addingTimeInterval(-3_600)
        let briefing = DepartureBriefing(leaveBy: optimizerFormatter.string(from: expected), driveMinutes: 34,
                                         tsaMinutes: 22, weatherLabel: "Clear", temperatureF: 74,
                                         flightNumber: "DL1423", originIATA: "LAS", computedAt: computedAt)

        let leaveBy = try #require(WidgetBridge.leaveBy(from: briefing, flights: [flight], now: computedAt.addingTimeInterval(600)))
        #expect(leaveBy.flightID == flight.id)
        #expect(leaveBy.leaveAt == expected)
        #expect(leaveBy.usesLiveTraffic)
        #expect(leaveBy.expiresAt == computedAt.addingTimeInterval(DepartureBriefing.maxAge))
        #expect(leaveBy.isLive(at: computedAt.addingTimeInterval(20 * 60)))
        #expect(!leaveBy.isLive(at: computedAt.addingTimeInterval(45 * 60)))

        let otherFlight = DepartureBriefing(leaveBy: briefing.leaveBy, driveMinutes: 34, tsaMinutes: 22,
                                            weatherLabel: "Clear", temperatureF: 74, flightNumber: "UA837",
                                            originIATA: "LAS", computedAt: computedAt)
        #expect(WidgetBridge.leaveBy(from: otherFlight, flights: [flight], now: computedAt) == nil)
        #expect(WidgetBridge.leaveBy(from: briefing, flights: [flight],
                                     now: computedAt.addingTimeInterval(DepartureBriefing.maxAge + 60)) == nil)
    }
}
