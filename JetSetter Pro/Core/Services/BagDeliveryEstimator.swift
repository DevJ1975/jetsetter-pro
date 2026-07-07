// File: Core/Services/BagDeliveryEstimator.swift
//
// Heuristic estimate of how long after landing a checked bag reaches the
// carousel. Mirrors the static-heuristic style of TSAWaitEstimator — there's
// no public airline/airport feed for this, so IRIS uses a reasonable model to
// time a ride to the curb. Carry-on only still returns a small deplane+walk-to-
// curb floor (never 0) so the car isn't dispatched at wheels-down.

import Foundation

enum BagDeliveryEstimator {

    struct Estimate {
        let minMinutes: Int
        let maxMinutes: Int
        /// Plain-language explanation of how the estimate was derived.
        let basis: String

        /// Midpoint, handy for timing a ride pickup.
        var expectedMinutes: Int { (minMinutes + maxMinutes) / 2 }

        var display: String {
            minMinutes == maxMinutes
                ? "\(minMinutes) min"
                : "\(minMinutes)–\(maxMinutes) min"
        }
    }

    /// Larger hubs take longer to walk from gate to claim and run bigger bag
    /// systems. A small tier-1 set bumps the estimate; everything else is typical.
    private static let largeHubs: Set<String> = [
        "ATL", "DFW", "ORD", "LAX", "JFK", "DEN", "SFO", "LAS", "SEA", "MIA",
        "EWR", "BOS", "MCO", "CLT", "IAH", "LHR", "CDG", "FRA", "AMS", "DXB",
        "HND", "NRT", "SIN", "HKG", "ICN", "PEK", "PVG"
    ]

    /// Busy mid-size airports that run larger-than-typical bag systems but aren't
    /// tier-1 mega-hubs. Recognized here so we don't lump them (and their longer
    /// waits) into the same band as small/regional fields.
    private static let midTierHubs: Set<String> = [
        "PHX", "MSP", "DTW", "PHL", "LGA", "BWI", "SAN", "DCA", "IAD", "TPA",
        "PDX", "SLC", "HNL", "AUS", "STL", "MDW", "YYZ", "YVR", "LGW", "MAN",
        "MUC", "BCN", "MAD", "FCO", "MXP", "ZRH", "DUB", "CPH", "OSL", "ARN"
    ]

    /// Returns the expected gap between wheels-down and bag-on-belt.
    ///
    /// - Parameters:
    ///   - airportIATA: Arrival airport code.
    ///   - hasCheckedBag: Whether the traveler checked a bag.
    ///   - isInternational: When true, the traveler clears immigration/customs
    ///     before reaching the carousel, which materially widens the wheels-down-
    ///     to-curb gap. IRIS uses `expectedMinutes` to time a ride, so an
    ///     international arrival must not be scheduled off a domestic midpoint.
    static func estimate(airportIATA: String, hasCheckedBag: Bool, isInternational: Bool = false) -> Estimate {
        let code = airportIATA.uppercased()
        let isLargeHub = largeHubs.contains(code)
        let isMidTier = midTierHubs.contains(code)

        // Even carry-on travelers need time to deplane, walk the concourse, and
        // reach the curb — feeding a literal 0 into ride timing dispatches the car
        // at wheels-down. Return a small hub-scaled walk-to-curb floor instead.
        guard hasCheckedBag else {
            if isInternational {
                // Immigration/customs stands between the jet bridge and the curb
                // even with nothing to claim.
                return Estimate(minMinutes: 25, maxMinutes: 50,
                                basis: "Carry-on only, international arrival — deplane, immigration/customs, and walk to the curb.")
            }
            if isLargeHub {
                return Estimate(minMinutes: 12, maxMinutes: 20,
                                basis: "Carry-on only at a large hub — deplane and walk to the curb.")
            }
            return Estimate(minMinutes: 8, maxMinutes: 15,
                            basis: "Carry-on only — deplane and walk to the curb.")
        }

        // International arrivals clear immigration (and often customs) BEFORE the
        // carousel, so the wheels-down-to-bag gap runs far longer than domestic.
        if isInternational {
            if isLargeHub {
                return Estimate(minMinutes: 50, maxMinutes: 90,
                                basis: "Large international hub (\(code)) — immigration/customs before claim, plus a big bag system.")
            }
            return Estimate(minMinutes: 40, maxMinutes: 75,
                            basis: "International arrival — immigration/customs clears before you reach the carousel.")
        }

        if isLargeHub {
            return Estimate(minMinutes: 20, maxMinutes: 35,
                            basis: "Large hub (\(code)) — longer walk and bigger bag system.")
        }
        if isMidTier {
            return Estimate(minMinutes: 15, maxMinutes: 30,
                            basis: "Busy airport (\(code)) — moderate walk and bag-system load.")
        }
        // Unrecognized code: we don't have hub-size data for it, so widen the band
        // and say so, letting IRIS pad its ride-timing buffer accordingly.
        return Estimate(minMinutes: 12, maxMinutes: 30,
                        basis: "Airport not in our size data (\(code)) — using a wider, lower-confidence estimate.")
    }
}
