// File: Core/Services/BagDeliveryEstimator.swift
//
// Heuristic estimate of how long after landing a checked bag reaches the
// carousel. Mirrors the static-heuristic style of TSAWaitEstimator — there's
// no public airline/airport feed for this, so IRIS uses a reasonable model to
// time a ride to the curb. Carry-on only → zero wait (you already have it).

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

    /// Returns the expected gap between wheels-down and bag-on-belt.
    static func estimate(airportIATA: String, hasCheckedBag: Bool) -> Estimate {
        guard hasCheckedBag else {
            return Estimate(minMinutes: 0, maxMinutes: 0,
                            basis: "Carry-on only — no carousel wait.")
        }
        let code = airportIATA.uppercased()
        if largeHubs.contains(code) {
            return Estimate(minMinutes: 20, maxMinutes: 35,
                            basis: "Large hub (\(code)) — longer walk and bigger bag system.")
        }
        return Estimate(minMinutes: 12, maxMinutes: 25,
                        basis: "Typical airport — first bags usually within ~15 minutes.")
    }
}
