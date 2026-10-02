// File: JetSetter ProTests/DisruptionMatchingTests.swift
//
// Covers the disruption monitor's network-free decisions: which FlightAware
// instance is the itinerary's flight, which disruptions are worth an alert,
// how repeat polls are deduped, and that the remembered gate survives a
// relaunch. Also pins the Live Activity start window. These are the rules
// that decide whether a traveler gets woken up, so they're tested without the
// network rather than left to a 10-minute background poll.

import Testing
import Foundation
@testable import JetSetter_Pro

@Suite(.serialized)
@MainActor
struct DisruptionMatchingTests {

    /// 2026-10-05 15:30 UTC: the itinerary's scheduled departure.
    private static let departure = Date(timeIntervalSince1970: 1_791_214_200)
    private static let day: TimeInterval = 86_400

    // MARK: - Fixtures

    private func makeFlight(
        id: String = "DAL1423-1791214200-schedule-0001",
        scheduledOut: Date? = DisruptionMatchingTests.departure,
        gate: String? = "B12",
        delayMinutes: Int? = 0,
        status: String = "Scheduled",
        cancelled: Bool = false,
        diverted: Bool = false,
        actualOut: Date? = nil,
        actualIn: Date? = nil
    ) -> Flight {
        Flight(
            faFlightId: id,
            ident: "DAL1423",
            identIata: "DL1423",
            operatorName: "Delta Air Lines",
            flightNumber: "1423",
            origin: Airport(code: "KLAS", codeIcao: "KLAS", codeIata: "LAS",
                            name: nil, city: "Las Vegas", timezone: "America/Los_Angeles"),
            destination: Airport(code: "KATL", codeIcao: "KATL", codeIata: "ATL",
                                 name: nil, city: "Atlanta", timezone: "America/New_York"),
            status: status,
            aircraftType: nil,
            gateOrigin: gate,
            gateDestination: nil,
            terminalOrigin: nil,
            terminalDestination: nil,
            baggageClaim: nil,
            departureDelay: delayMinutes.map { $0 * 60 },
            arrivalDelay: nil,
            progressPercent: nil,
            cancelled: cancelled,
            diverted: diverted,
            scheduledOut: scheduledOut,
            estimatedOut: nil,
            actualOut: actualOut,
            scheduledIn: scheduledOut.map { $0.addingTimeInterval(4 * 3600) },
            estimatedIn: nil,
            actualIn: actualIn
        )
    }

    /// FlightAware's typical answer for a daily flight: yesterday's, today's
    /// and tomorrow's instances, each with its own id.
    private func threeDailyInstances() -> [Flight] {
        [
            makeFlight(id: "day-before", scheduledOut: Self.departure.addingTimeInterval(-Self.day)),
            makeFlight(id: "day-of", scheduledOut: Self.departure.addingTimeInterval(20 * 60)),
            makeFlight(id: "day-after", scheduledOut: Self.departure.addingTimeInterval(Self.day))
        ]
    }

    private func throwawayDefaults() -> (UserDefaults, String) {
        let name = "DisruptionMatchingTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name) ?? .standard, name)
    }

    // MARK: - Instance matching

    /// Regression: the monitor took `flights.first` from FlightAware, so a
    /// traveler on today's DL1423 got yesterday's delay or tomorrow's
    /// cancellation. The instance within ±12 h of the itinerary must win.
    @Test func picksTheInstanceForTheItineraryDayFromDayBeforeDayOfAndDayAfter() {
        let instances = threeDailyInstances()

        let today = DisruptionMatching.matchingInstance(in: instances, scheduledDeparture: Self.departure)
        #expect(today?.faFlightId == "day-of")

        let yesterday = DisruptionMatching.matchingInstance(
            in: instances, scheduledDeparture: Self.departure.addingTimeInterval(-Self.day)
        )
        #expect(yesterday?.faFlightId == "day-before")

        let tomorrow = DisruptionMatching.matchingInstance(
            in: instances, scheduledDeparture: Self.departure.addingTimeInterval(Self.day)
        )
        #expect(tomorrow?.faFlightId == "day-after")
    }

    @Test func toleratesAnItineraryTimeThatIsOffByAFewHours() {
        // A pasted booking read in the wrong zone can be hours out; it's still today's flight.
        let match = DisruptionMatching.matchingInstance(
            in: threeDailyInstances(), scheduledDeparture: Self.departure.addingTimeInterval(3 * 3600)
        )
        #expect(match?.faFlightId == "day-of")
    }

    /// Regression: with no same-day instance listed, the monitor alerted on
    /// whatever instance came first. Now nothing matches, so nothing alerts.
    @Test func findsNoMatchWhenOnlyOtherDaysAreListed() {
        let otherDays = [
            makeFlight(id: "day-before", scheduledOut: Self.departure.addingTimeInterval(-Self.day)),
            makeFlight(id: "day-after", scheduledOut: Self.departure.addingTimeInterval(Self.day)),
            makeFlight(id: "no-schedule", scheduledOut: nil)
        ]
        #expect(DisruptionMatching.matchingInstance(in: otherDays, scheduledDeparture: Self.departure) == nil)
    }

    @Test func monitorsLegsFromSixHoursAgoToADayAhead() {
        let now = Self.departure
        #expect(DisruptionMatching.shouldMonitor(departure: now.addingTimeInterval(-5 * 3600), now: now))
        #expect(DisruptionMatching.shouldMonitor(departure: now.addingTimeInterval(20 * 3600), now: now))
        #expect(!DisruptionMatching.shouldMonitor(departure: now.addingTimeInterval(-7 * 3600), now: now))
        #expect(!DisruptionMatching.shouldMonitor(departure: now.addingTimeInterval(3 * Self.day), now: now))
    }

    // MARK: - Detection

    /// Regression: landed flights kept being polled and a delay that was
    /// history still produced alerts.
    @Test func aLandedFlightProducesNoAlert() {
        let atGate = makeFlight(delayMinutes: 90, status: "Arrived / Gate Arrival",
                                actualOut: Self.departure, actualIn: Self.departure.addingTimeInterval(4 * 3600))
        #expect(DisruptionMatching.detectAlerts(flight: atGate, previousGate: "A1", nextDeparture: nil).isEmpty)

        // AeroAPI can say "Landed" before it has a gate-in time.
        let taxiing = makeFlight(delayMinutes: 90, status: "Landed / Taxiing", actualOut: Self.departure)
        #expect(DisruptionMatching.detectAlerts(flight: taxiing, previousGate: nil, nextDeparture: nil).isEmpty)
    }

    /// Regression: `diverted` was decoded but never read.
    @Test func aDivertedFlightAlertsEvenAfterLanding() {
        let diverted = makeFlight(status: "Diverted", diverted: true,
                                  actualOut: Self.departure, actualIn: Self.departure.addingTimeInterval(3 * 3600))
        let alerts = DisruptionMatching.detectAlerts(flight: diverted, previousGate: nil, nextDeparture: nil)
        #expect(alerts.map(\.type) == [.diversion])
    }

    @Test func aCancellationIsTheOnlyAlertForACancelledFlight() {
        let cancelled = makeFlight(gate: "C4", delayMinutes: 120, cancelled: true)
        let alerts = DisruptionMatching.detectAlerts(flight: cancelled, previousGate: "B12", nextDeparture: nil)
        #expect(alerts == [DisruptionAlert(type: .cancellation, value: "cancelled")])
    }

    @Test func delaysFallIntoBucketsFromFortyFiveMinutes() {
        #expect(DisruptionMatching.delayBucket(minutes: 44) == nil)
        #expect(DisruptionMatching.delayBucket(minutes: 45) == 45)
        #expect(DisruptionMatching.delayBucket(minutes: 89) == 45)
        #expect(DisruptionMatching.delayBucket(minutes: 95) == 90)
        #expect(DisruptionMatching.delayBucket(minutes: 400) == 360)
    }

    @Test func gateComparisonIgnoresSpacingCaseAndPlaceholders() {
        let flight = makeFlight(gate: "b 12")
        #expect(DisruptionMatching.detectAlerts(flight: flight, previousGate: "B12", nextDeparture: nil).isEmpty)
        #expect(DisruptionMatching.detectAlerts(flight: flight, previousGate: "—", nextDeparture: nil).isEmpty)
        #expect(DisruptionMatching.normalizedGate("TBD") == nil)
    }

    // MARK: - Dedupe

    /// Regression: a 45-minute-plus delay created a new event and played the
    /// cabin chime on every 10-minute poll. The same bucket must stay quiet; a
    /// bigger one alerts again; a shrinking delay doesn't.
    @Test func aRepeatPollWithTheSameDelayDoesNotAlertButABiggerBucketDoes() {
        var ledger = DisruptionAlertLedger()
        let key = "DAL1423-today"
        let now = Self.departure

        func pollAlerts(delay: Int) -> [DisruptionAlert] {
            DisruptionMatching.detectAlerts(flight: makeFlight(delayMinutes: delay), previousGate: "B12", nextDeparture: nil)
                .filter { ledger.shouldSend($0, flightKey: key) }
        }

        let first = pollAlerts(delay: 50)
        #expect(first == [DisruptionAlert(type: .majorDelay, value: "45")])
        first.forEach { ledger.recordSent($0, flightKey: key, at: now) }

        #expect(pollAlerts(delay: 50).isEmpty)
        #expect(pollAlerts(delay: 70).isEmpty)

        let bigger = pollAlerts(delay: 100)
        #expect(bigger == [DisruptionAlert(type: .majorDelay, value: "90")])
        bigger.forEach { ledger.recordSent($0, flightKey: key, at: now) }

        #expect(pollAlerts(delay: 60).isEmpty)
    }

    @Test func aDelayOnAnotherDaysInstanceIsNotSuppressed() {
        var ledger = DisruptionAlertLedger()
        let alert = DisruptionAlert(type: .majorDelay, value: "45")
        ledger.recordSent(alert, flightKey: "yesterday", at: Self.departure)
        #expect(ledger.shouldSend(alert, flightKey: "today"))
    }

    @Test func aGateChangeAlertsOncePerNewGate() {
        var ledger = DisruptionAlertLedger()
        let key = "DAL1423-today"
        let toC4 = DisruptionAlert(type: .gateChange, value: "C4")
        #expect(ledger.shouldSend(toC4, flightKey: key))
        ledger.recordSent(toC4, flightKey: key, at: Self.departure)
        #expect(!ledger.shouldSend(toC4, flightKey: key))
        #expect(ledger.shouldSend(DisruptionAlert(type: .gateChange, value: "D1"), flightKey: key))
    }

    @Test func pruningDropsEntriesOlderThanTheRetentionWindow() {
        var ledger = DisruptionAlertLedger()
        let old = Self.departure.addingTimeInterval(-5 * Self.day)
        ledger.recordSent(DisruptionAlert(type: .cancellation, value: "cancelled"), flightKey: "old", at: old)
        ledger.recordGate("A1", flightKey: "old", at: old)
        ledger.recordGate("B12", flightKey: "recent", at: Self.departure)

        ledger.prune(now: Self.departure)

        #expect(ledger.alerts.isEmpty)
        #expect(ledger.knownGate(flightKey: "old") == nil)
        #expect(ledger.knownGate(flightKey: "recent") == "B12")
    }

    // MARK: - Persistence

    /// Regression: `lastKnownGates` lived only in memory, so after a background
    /// relaunch the monitor had no previous gate and missed the change.
    @Test func theGateCacheSurvivesAReinit() {
        let (defaults, suiteName) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "DAL1423-today"

        DisruptionAlertLedgerStore(defaults: defaults).mutate(now: Self.departure) { ledger in
            ledger.recordGate("B12", flightKey: key, at: Self.departure)
        }

        // A fresh store stands in for the relaunched process.
        let relaunched = DisruptionAlertLedgerStore(defaults: defaults)
        let previousGate = relaunched.ledger.knownGate(flightKey: key)
        #expect(previousGate == "B12")

        let alerts = DisruptionMatching.detectAlerts(
            flight: makeFlight(gate: "C4"), previousGate: previousGate, nextDeparture: nil
        )
        #expect(alerts == [DisruptionAlert(type: .gateChange, value: "C4")])
    }

    @Test func sentAlertsSurviveAReinit() {
        let (defaults, suiteName) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let alert = DisruptionAlert(type: .majorDelay, value: "45")

        DisruptionAlertLedgerStore(defaults: defaults).mutate(now: Self.departure) { ledger in
            ledger.recordSent(alert, flightKey: "today", at: Self.departure)
        }

        #expect(!DisruptionAlertLedgerStore(defaults: defaults).ledger.shouldSend(alert, flightKey: "today"))
    }

    // MARK: - Flight keys

    @Test func flightKeyPrefersTheFlightAwareId() {
        let key = DisruptionAlertLedger.flightKey(
            faFlightId: "DAL1423-1791214200-schedule-0001", flightNumber: "DL1423",
            scheduledDeparture: Self.departure, originTimeZone: nil
        )
        #expect(key == "DAL1423-1791214200-schedule-0001")
    }

    @Test func fallbackFlightKeyUsesTheOriginAirportsLocalDate() {
        // 23:30 in Las Vegas on Oct 5 is already Oct 6 in UTC.
        let lateEvening = Date(timeIntervalSince1970: 1_791_268_200)
        let lasKey = DisruptionAlertLedger.flightKey(
            faFlightId: "", flightNumber: "dl1423",
            scheduledDeparture: lateEvening, originTimeZone: TimeZone(identifier: "America/Los_Angeles")
        )
        #expect(lasKey == "DL1423#2026-10-05")

        let unknownZoneKey = DisruptionAlertLedger.flightKey(
            faFlightId: nil, flightNumber: "DL1423",
            scheduledDeparture: lateEvening, originTimeZone: nil
        )
        #expect(unknownZoneKey == "DL1423#2026-10-06")
    }

    // MARK: - Live Activity

    /// Regression: the Live Activity started at check-in (often 24 h out) and
    /// iOS ended it after 8 h, before the flight. It now starts within 4 h.
    @Test func liveActivityIsOnlyDueWithinFourHoursOfDeparture() {
        let now = Self.departure
        #expect(FlightLiveActivityService.isDue(departure: now.addingTimeInterval(3 * 3600), now: now))
        #expect(!FlightLiveActivityService.isDue(departure: now.addingTimeInterval(5 * 3600), now: now))
        #expect(!FlightLiveActivityService.isDue(departure: now.addingTimeInterval(24 * 3600), now: now))
        #expect(!FlightLiveActivityService.isDue(departure: now.addingTimeInterval(-2 * 3600), now: now))
    }

    /// Regression: the card said "On Time" with no live data behind it.
    @Test func liveActivityStatusComesOnlyFromRealData() {
        #expect(DisruptionMatching.liveActivityStatus(for: makeFlight(delayMinutes: nil)) == .scheduled)
        #expect(DisruptionMatching.liveActivityStatus(for: makeFlight(delayMinutes: 5)) == .onTime)
        #expect(DisruptionMatching.liveActivityStatus(for: makeFlight(delayMinutes: 30)) == .delayed)
        #expect(DisruptionMatching.liveActivityStatus(for: makeFlight(cancelled: true)) == .cancelled)
        #expect(DisruptionMatching.liveActivityStatus(for: makeFlight(diverted: true)) == .diverted)
        #expect(DisruptionMatching.liveActivityStatus(for: makeFlight(actualOut: Self.departure)) == nil)
    }
}
