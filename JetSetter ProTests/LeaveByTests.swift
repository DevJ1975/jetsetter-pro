// File: JetSetter ProTests/LeaveByTests.swift
//
// Covers the leave-by arithmetic in `LeaveByPlanner`: international detection
// from airport countries, the bag-drop cutoff racing the security path, and
// the fallback when MapKit has no drive time. The MapKit and weather legs of
// `DepartureOptimizerService` can't run in a test host, which is why the maths
// lives in a pure type.

import Testing
import Foundation
@testable import JetSetter_Pro

@Suite
@MainActor
struct LeaveByTests {

    /// A fixed departure so every expectation is exact arithmetic.
    private let departure = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutesBefore(_ minutes: Int) -> Date {
        departure.addingTimeInterval(-TimeInterval(minutes) * 60)
    }

    // MARK: - International detection

    /// Defect: `recommend(isInternational:)` existed but no caller passed it,
    /// so a JFK–LHR departure got domestic buffers.
    @Test func flightsBetweenCountriesAreInternational() {
        #expect(LeaveByPlanner.isInternational(originIATA: "JFK", destinationIATA: "LHR"))
        #expect(LeaveByPlanner.isInternational(originIATA: "SEA", destinationIATA: "YVR"))
        #expect(LeaveByPlanner.isInternational(originIATA: "PEK", destinationIATA: "HKG"))
    }

    @Test func flightsWithinOneCountryAreDomestic() {
        #expect(!LeaveByPlanner.isInternational(originIATA: "LAS", destinationIATA: "ATL"))
        #expect(!LeaveByPlanner.isInternational(originIATA: "LAX", destinationIATA: "HNL"))
        #expect(!LeaveByPlanner.isInternational(originIATA: "nrt", destinationIATA: " KIX "))
    }

    @Test func anUnknownAirportFallsBackToDomestic() {
        #expect(!LeaveByPlanner.isInternational(originIATA: "LAS", destinationIATA: "XYZ"))
        #expect(!LeaveByPlanner.isInternational(originIATA: "JFK", destinationIATA: nil))
        #expect(!LeaveByPlanner.isInternational(originIATA: nil, destinationIATA: "LHR"))
    }

    @Test func airportCountriesAreISOCodesAndUnknownCodesAreNil() {
        #expect(AirportCoordinates.countryCode(for: "lhr") == "GB")
        #expect(AirportCoordinates.countryCode(for: "YYZ") == "CA")
        #expect(AirportCoordinates.countryCode(for: "ZZZ") == nil)
    }

    // MARK: - Buffers

    @Test func domesticDeparturesUseTheStandardBuffers() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 30 * 60,
            tsaWaitMinutes: 20, isInternational: false, checkingBag: false
        )
        #expect(plan.boardingBufferMinutes == 30)
        #expect(plan.curbBufferMinutes == 10)
        // 30 at the gate + 20 security + 10 curb + 30 drive.
        #expect(plan.leaveAt == minutesBefore(90))
        #expect(plan.arriveAtGateAt == minutesBefore(30))
        #expect(plan.bindingConstraint == .security)
    }

    @Test func internationalDeparturesUseTheWiderBuffers() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 30 * 60,
            tsaWaitMinutes: 20, isInternational: true, checkingBag: false
        )
        #expect(plan.isInternational)
        #expect(plan.boardingBufferMinutes == 60)
        #expect(plan.curbBufferMinutes == 20)
        // 60 at the gate + 20 security + 20 curb + 30 drive.
        #expect(plan.leaveAt == minutesBefore(130))
    }

    @Test func explicitBufferOverridesBeatTheDefaults() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 0,
            tsaWaitMinutes: 0, isInternational: true, checkingBag: false,
            boardingBufferMinutes: 40, curbBufferMinutes: 5
        )
        #expect(plan.boardingBufferMinutes == 40)
        #expect(plan.curbBufferMinutes == 5)
        #expect(plan.leaveAt == minutesBefore(45))
    }

    // MARK: - Bag drop

    /// Defect: there was no bag-drop cutoff at all. A PreCheck traveler with a
    /// five-minute line was told to arrive 45 minutes out, by which time the
    /// domestic bag drop had already closed.
    @Test func theBagDropCutoffWinsWhenItNeedsTheTravelerOutEarlier() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 30 * 60,
            tsaWaitMinutes: 5, isInternational: false, checkingBag: true
        )
        // Security path: 30 + 5 + 10 + 30 = 75. Bag drop: 45 + 10 + 30 = 85.
        #expect(plan.bagDropDeadline == minutesBefore(45))
        #expect(plan.leaveAt == minutesBefore(85))
        #expect(plan.bindingConstraint == .bagDrop)
    }

    @Test func theSecurityPathWinsWhenItIsEarlierButTheBagDeadlineIsStillReported() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 30 * 60,
            tsaWaitMinutes: 30, isInternational: false, checkingBag: true
        )
        // Security path: 30 + 30 + 10 + 30 = 100. Bag drop: 45 + 10 + 30 = 85.
        #expect(plan.leaveAt == minutesBefore(100))
        #expect(plan.bindingConstraint == .security)
        #expect(plan.bagDropDeadline == minutesBefore(45))
    }

    @Test func internationalBagDropClosesAnHourBeforeDeparture() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 30 * 60,
            tsaWaitMinutes: 0, isInternational: true, checkingBag: true,
            boardingBufferMinutes: 20
        )
        // Security path: 20 + 0 + 20 + 30 = 70. Bag drop: 60 + 20 + 30 = 110.
        #expect(plan.bagDropDeadline == minutesBefore(60))
        #expect(plan.leaveAt == minutesBefore(110))
        #expect(plan.bindingConstraint == .bagDrop)
    }

    @Test func withoutACheckedBagThereIsNoBagDropDeadline() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 30 * 60,
            tsaWaitMinutes: 5, isInternational: false, checkingBag: false
        )
        #expect(plan.bagDropDeadline == nil)
        #expect(plan.bindingConstraint == .security)
        #expect(plan.leaveAt == minutesBefore(75))
    }

    @Test func onlyUndroppedBagsBookedOnThisFlightCountAsChecked() {
        #expect(LeaveByPlanner.hasBagToDrop(
            flightNumber: "DL1423", bags: [(flightNumber: "dl 1423", isHandedOver: false)]))
        // Already handed over at the counter: the cutoff no longer applies.
        #expect(!LeaveByPlanner.hasBagToDrop(
            flightNumber: "DL1423", bags: [(flightNumber: "DL1423", isHandedOver: true)]))
        // No flight number could be a carry-on.
        #expect(!LeaveByPlanner.hasBagToDrop(
            flightNumber: "DL1423", bags: [(flightNumber: nil, isHandedOver: false)]))
        #expect(!LeaveByPlanner.hasBagToDrop(
            flightNumber: "DL1423", bags: [(flightNumber: "UA55", isHandedOver: false)]))
        #expect(!LeaveByPlanner.hasBagToDrop(
            flightNumber: nil, bags: [(flightNumber: "DL1423", isHandedOver: false)]))
    }

    // MARK: - Drive time

    /// Defect: when MapKit's ETA failed the service silently assumed a
    /// 30-minute drive and the screen still said "Drive (live traffic)".
    @Test func aFailedDriveTimeIsAPessimisticEstimateAndNeverLive() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: nil,
            tsaWaitMinutes: 15, isInternational: false, checkingBag: false
        )
        #expect(!plan.isDriveTimeLive)
        #expect(plan.driveMinutes == LeaveByPlanner.fallbackDriveMinutes)
        #expect(LeaveByPlanner.fallbackDriveMinutes >= 60)
        // 30 + 15 + 10 + 60.
        #expect(plan.leaveAt == minutesBefore(115))
    }

    @Test func aMapKitDriveTimeIsLive() {
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: departure, liveDriveSeconds: 42 * 60,
            tsaWaitMinutes: 15, isInternational: false, checkingBag: false
        )
        #expect(plan.isDriveTimeLive)
        #expect(plan.driveMinutes == 42)
    }
}
