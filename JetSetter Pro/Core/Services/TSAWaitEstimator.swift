// File: Core/Services/TSAWaitEstimator.swift
//
// Estimates TSA security wait times for US airports using a heuristic model:
//   • Airport-tier base wait (top 30 airports = "tier 1", mid = "tier 2", small = "tier 3")
//   • Time-of-day multiplier (peak hours raise the wait)
//   • Day-of-week modifier (Mondays / Fridays / Sundays are heavier)
//   • PreCheck / CLEAR modifiers (-60% / -50% respectively)
//
// The MyTSA endpoint is unreliable / rate-limited, so we use this heuristic.
// When MyTSA returns valid data we can fold it in here later.

import Foundation

enum SecurityLane {
    case standard, preCheck, clear, clearPlusPreCheck

    var multiplier: Double {
        switch self {
        case .standard:           return 1.0
        case .preCheck:           return 0.4
        case .clear:              return 0.5
        case .clearPlusPreCheck:  return 0.2
        }
    }

    var label: String {
        switch self {
        case .standard:           return "Standard"
        case .preCheck:           return "TSA PreCheck"
        case .clear:              return "CLEAR"
        case .clearPlusPreCheck:  return "CLEAR + PreCheck"
        }
    }
}

struct TSAWaitEstimate {
    let minMinutes: Int
    let maxMinutes: Int
    let confidence: Confidence
    let basis: String

    enum Confidence { case high, medium, low }

    /// Pick the midpoint to use as the single number when planning.
    var midpoint: Int { (minMinutes + maxMinutes) / 2 }

    var display: String {
        "\(minMinutes)–\(maxMinutes) min"
    }
}

enum TSAWaitEstimator {

    /// Returns the estimated security wait for the given airport at the given
    /// arrival time, on the given lane.
    static func estimate(
        airportIATA: String,
        arrivingAt date: Date,
        lane: SecurityLane = .standard
    ) -> TSAWaitEstimate {
        let tier = AirportTier.of(iata: airportIATA)
        let baseRange = tier.baseWaitRange
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)  // 1 = Sunday, 7 = Saturday

        let timeMultiplier = peakMultiplier(for: hour)
        let dayMultiplier = dayMultiplier(for: weekday)
        let laneMultiplier = lane.multiplier
        let combined = timeMultiplier * dayMultiplier * laneMultiplier

        let minMins = max(3, Int(Double(baseRange.lowerBound) * combined))
        let maxMins = max(8, Int(Double(baseRange.upperBound) * combined))

        let confidence: TSAWaitEstimate.Confidence = tier == .unknown ? .low : .medium
        let basis = "\(tier.label) airport, \(timeOfDayLabel(for: hour)), \(lane.label)"

        return TSAWaitEstimate(
            minMinutes: minMins,
            maxMinutes: maxMins,
            confidence: confidence,
            basis: basis
        )
    }

    // MARK: - Tiers

    enum AirportTier {
        case tier1, tier2, tier3, unknown

        var label: String {
            switch self {
            case .tier1:    return "major hub"
            case .tier2:    return "mid-size"
            case .tier3:    return "small/regional"
            case .unknown:  return "unrated"
            }
        }

        /// Off-peak baseline wait window in minutes.
        var baseWaitRange: ClosedRange<Int> {
            switch self {
            case .tier1:    return 15...30
            case .tier2:    return 8...18
            case .tier3:    return 5...12
            case .unknown:  return 10...25
            }
        }

        static func of(iata: String) -> AirportTier {
            let code = iata.uppercased()
            if Self.tier1Airports.contains(code) { return .tier1 }
            if Self.tier2Airports.contains(code) { return .tier2 }
            if Self.tier3Airports.contains(code) { return .tier3 }
            return .unknown
        }

        /// US top-25 by 2024 passenger volume.
        private static let tier1Airports: Set<String> = [
            "ATL", "DFW", "DEN", "ORD", "LAX", "JFK", "LAS", "MCO", "MIA", "CLT",
            "SEA", "PHX", "EWR", "SFO", "IAH", "BOS", "MSP", "FLL", "LGA", "DTW",
            "PHL", "SLC", "BWI", "DCA", "IAD"
        ]
        /// Mid-volume US airports.
        private static let tier2Airports: Set<String> = [
            "SAN", "TPA", "MDW", "BNA", "AUS", "PDX", "STL", "HNL", "RDU", "OAK",
            "MSY", "SMF", "SJC", "PIT", "CLE", "IND", "CMH", "MKE", "JAX", "MEM",
            "MCI", "ABQ"
        ]
        /// Smaller regional US airports.
        private static let tier3Airports: Set<String> = [
            "BUR", "ONT", "SNA", "LGB", "PVD", "BUF", "ALB", "BDL", "SYR",
            "SAV", "GSO", "GSP", "CHA", "BHM", "TUL", "OKC", "DSM"
        ]
    }

    // MARK: - Modifiers

    /// Multiplier ≥ 1.0 during peak hours; ≤ 1.0 in off-peak.
    private static func peakMultiplier(for hour: Int) -> Double {
        switch hour {
        case 5...7:    return 1.7  // morning rush
        case 8...10:   return 1.3
        case 11...14:  return 1.0
        case 15...17:  return 1.4
        case 18...20:  return 1.6  // evening rush
        case 21...23:  return 0.8
        default:       return 0.6  // overnight
        }
    }

    /// Mondays and Fridays are heaviest; Saturdays are lightest.
    private static func dayMultiplier(for weekday: Int) -> Double {
        switch weekday {
        case 1:  return 1.15  // Sunday — high evening returns
        case 2:  return 1.20  // Monday
        case 3:  return 1.00  // Tuesday
        case 4:  return 1.00  // Wednesday
        case 5:  return 1.10  // Thursday
        case 6:  return 1.25  // Friday
        case 7:  return 0.85  // Saturday
        default: return 1.0
        }
    }

    private static func timeOfDayLabel(for hour: Int) -> String {
        switch hour {
        case 5...7:    return "early-morning peak"
        case 8...10:   return "morning"
        case 11...14:  return "midday"
        case 15...17:  return "afternoon"
        case 18...20:  return "evening peak"
        case 21...23:  return "late evening"
        default:       return "overnight"
        }
    }
}
