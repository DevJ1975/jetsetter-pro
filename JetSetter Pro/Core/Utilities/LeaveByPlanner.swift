// File: Core/Utilities/LeaveByPlanner.swift
//
// The arithmetic behind "Leave by 5:42 PM", kept free of MapKit, weather and
// location so it can be tested. `DepartureOptimizerService` gathers the live
// inputs (drive ETA, security wait) and hands them here.
//
// Three defects shaped it:
//   • When MapKit's ETA failed, the service quietly assumed a 30-minute drive
//     and the UI still said "Drive (live traffic)". A failed ETA now becomes a
//     pessimistic 60-minute estimate, and the plan says it isn't live so no
//     screen can label it as traffic data.
//   • International buffers existed but no caller ever switched them on.
//     `isInternational(originIATA:destinationIATA:)` now works it out from the
//     airports' countries. Unknown airports fall back to domestic buffers.
//   • Nothing modelled the bag-drop cutoff. A traveler checking a bag must
//     reach the counter 45 minutes (domestic) or 60 minutes (international)
//     before departure. That deadline can bind before the security path does
//     (a PreCheck traveler with a short line), so the plan takes the earlier
//     of the two leave times.

import Foundation

nonisolated enum LeaveByPlanner {

    // MARK: - Tunables

    /// Drive time assumed when MapKit can't give an ETA (offline, captive
    /// portal, routing error). Deliberately pessimistic: an early arrival costs
    /// a coffee, a late one costs the flight.
    static let fallbackDriveMinutes = 60

    static let domesticBoardingBufferMinutes = 30
    static let internationalBoardingBufferMinutes = 60
    static let domesticCurbBufferMinutes = 10
    static let internationalCurbBufferMinutes = 20

    /// Common airline bag-drop cutoffs. Some carriers are stricter (a few close
    /// international bag drop at 75–90 minutes), so this is a floor, not a promise.
    static let domesticBagDropCutoffMinutes = 45
    static let internationalBagDropCutoffMinutes = 60

    // MARK: - Result

    /// Which deadline set the leave-by time.
    nonisolated enum Constraint: Equatable {
        /// Security line plus being at the gate before boarding.
        case security
        /// Reaching the bag-drop counter before the airline's cutoff.
        case bagDrop
    }

    nonisolated struct Plan: Equatable {
        let leaveAt: Date
        /// Drive time actually used: MapKit's when live, the fallback otherwise.
        let driveSeconds: TimeInterval
        /// False when MapKit failed and `driveSeconds` is the fallback estimate.
        /// UI must never call a non-live drive "live traffic".
        let isDriveTimeLive: Bool
        let isInternational: Bool
        let checkingBag: Bool
        let boardingBufferMinutes: Int
        let curbBufferMinutes: Int
        /// When the traveler should be at the gate.
        let arriveAtGateAt: Date
        /// Last moment to hand over a checked bag; nil when not checking one.
        let bagDropDeadline: Date?
        let bindingConstraint: Constraint

        var driveMinutes: Int { Int(driveSeconds / 60) }
    }

    // MARK: - International detection

    /// True only when both airports are known and sit in different countries.
    /// An unknown airport returns false so the caller uses domestic buffers, as
    /// agreed; the bag-drop cutoff still protects a traveler with a checked bag.
    static func isInternational(originIATA: String?, destinationIATA: String?) -> Bool {
        guard let origin = originIATA, let destination = destinationIATA,
              let originCountry = AirportCoordinates.countryCode(for: origin),
              let destinationCountry = AirportCoordinates.countryCode(for: destination)
        else { return false }
        return originCountry != destinationCountry
    }

    static func bagDropCutoffMinutes(isInternational: Bool) -> Int {
        isInternational ? internationalBagDropCutoffMinutes : domesticBagDropCutoffMinutes
    }

    /// The drive time to plan with: MapKit's live ETA when there is one,
    /// otherwise the pessimistic fallback.
    static func effectiveDriveSeconds(live: TimeInterval?) -> TimeInterval {
        live ?? TimeInterval(fallbackDriveMinutes * 60)
    }

    // MARK: - Plan

    /// Works backwards from the scheduled departure.
    ///
    /// - Security path: gate by (departure − boarding buffer), so enter the
    ///   security line `tsaWaitMinutes` earlier, reach the curb `curb` minutes
    ///   before that, and leave one drive earlier still.
    /// - Bag-drop path (only when `checkingBag`): reach the counter by
    ///   (departure − cutoff), so reach the curb `curb` minutes before that and
    ///   leave one drive earlier.
    ///
    /// The earlier leave time wins. Buffer overrides replace the domestic or
    /// international defaults when given.
    static func plan(
        scheduledDeparture: Date,
        liveDriveSeconds: TimeInterval?,
        tsaWaitMinutes: Int,
        isInternational: Bool,
        checkingBag: Bool,
        boardingBufferMinutes: Int? = nil,
        curbBufferMinutes: Int? = nil
    ) -> Plan {
        let boarding = boardingBufferMinutes
            ?? (isInternational ? internationalBoardingBufferMinutes : domesticBoardingBufferMinutes)
        let curb = curbBufferMinutes
            ?? (isInternational ? internationalCurbBufferMinutes : domesticCurbBufferMinutes)
        let drive = effectiveDriveSeconds(live: liveDriveSeconds)

        let arriveAtGateAt = scheduledDeparture.addingTimeInterval(-minutes(boarding))
        let securityLeaveAt = arriveAtGateAt
            .addingTimeInterval(-minutes(tsaWaitMinutes))
            .addingTimeInterval(-minutes(curb))
            .addingTimeInterval(-drive)

        var leaveAt = securityLeaveAt
        var binding = Constraint.security
        var bagDropDeadline: Date?

        if checkingBag {
            let deadline = scheduledDeparture.addingTimeInterval(
                -minutes(bagDropCutoffMinutes(isInternational: isInternational))
            )
            bagDropDeadline = deadline
            let bagLeaveAt = deadline
                .addingTimeInterval(-minutes(curb))
                .addingTimeInterval(-drive)
            if bagLeaveAt < securityLeaveAt {
                leaveAt = bagLeaveAt
                binding = .bagDrop
            }
        }

        return Plan(
            leaveAt: leaveAt,
            driveSeconds: drive,
            isDriveTimeLive: liveDriveSeconds != nil,
            isInternational: isInternational,
            checkingBag: checkingBag,
            boardingBufferMinutes: boarding,
            curbBufferMinutes: curb,
            arriveAtGateAt: arriveAtGateAt,
            bagDropDeadline: bagDropDeadline,
            bindingConstraint: binding
        )
    }

    // MARK: - Checked bags

    /// Whether the luggage tracker holds a bag for this flight that still has
    /// to be dropped. Bags are tied to flights by flight number ("DL 1423" and
    /// "dl1423" match). A bag with no flight number may be a carry-on, so it
    /// doesn't count, and one already checked in or further along has been
    /// handed over, so the bag-drop deadline no longer applies to it.
    static func hasBagToDrop(flightNumber: String?, bags: [(flightNumber: String?, isHandedOver: Bool)]) -> Bool {
        guard let wanted = normalizedFlightNumber(flightNumber) else { return false }
        return bags.contains { bag in
            !bag.isHandedOver && normalizedFlightNumber(bag.flightNumber) == wanted
        }
    }

    private static func normalizedFlightNumber(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let compact = raw.uppercased().filter { !$0.isWhitespace }
        return compact.isEmpty ? nil : compact
    }

    private static func minutes(_ value: Int) -> TimeInterval {
        TimeInterval(value) * 60
    }
}
