// File: Core/Services/Learning/TravelProfile.swift
//
// The derived, human-readable profile IRIS learns about the traveler. It is
// computed from TravelSignals + the history already on device (boarding passes,
// trips, expenses) by TravelProfileEngine — never hand-edited. The user "corrects"
// it by deleting signals / turning learning off. `summaryForPrompt()` mirrors the
// style of IRISContext so it can be injected into IRIS's system instructions.

import Foundation

// MARK: - Weighted value

/// A learned value plus how strongly (recency-weighted) and often it's been seen.
nonisolated struct WeightedValue: Codable, Equatable, Identifiable {
    var id: String { value }
    let value: String
    let weight: Double
    let count: Int
}

// MARK: - Seat preference

nonisolated enum SeatColumn: String, Codable {
    case window, aisle, middle, unknown
    var displayName: String {
        switch self {
        case .window: return "window"
        case .aisle:  return "aisle"
        case .middle: return "middle"
        case .unknown: return "no clear"
        }
    }
}

nonisolated enum SeatZone: String, Codable {
    case forward, mid, rear, unknown
    var displayName: String {
        switch self {
        case .forward: return "forward cabin"
        case .mid:     return "mid cabin"
        case .rear:    return "rear cabin"
        case .unknown: return ""
        }
    }
}

nonisolated struct SeatPreference: Codable, Equatable {
    var column: SeatColumn
    var zone: SeatZone
    /// 0...1 — share of observations matching the dominant column.
    var confidence: Double
    var sampleSize: Int

    var displayName: String {
        let z = zone.displayName
        let base = "\(column.displayName) seat"
        return z.isEmpty ? base : "\(base), \(z)"
    }
}

// MARK: - Spend stat

nonisolated struct SpendStat: Codable, Equatable, Identifiable {
    var id: String { "\(category)|\(currency)" }
    let category: String
    let currency: String
    let average: Double
    let count: Int
}

// MARK: - Travel profile

nonisolated struct TravelProfile: Codable, Equatable {
    var typicalSeat: SeatPreference?
    var topAirlines: [WeightedValue]
    var topHotelBrands: [WeightedValue]
    var preferredCabin: String?
    var frequentCities: [WeightedValue]
    var spendByCategory: [SpendStat]
    var typicalBookingLeadDays: Int?
    /// Trip rhythm (Phase 3) — derived from completed/known trips.
    var typicalTripDurationDays: Int?
    var travelCadenceDays: Int?
    var peakTravelMonths: [String]
    var generatedAt: Date

    static func empty(at date: Date = Date()) -> TravelProfile {
        TravelProfile(typicalSeat: nil, topAirlines: [], topHotelBrands: [],
                      preferredCabin: nil, frequentCities: [], spendByCategory: [],
                      typicalBookingLeadDays: nil, typicalTripDurationDays: nil,
                      travelCadenceDays: nil, peakTravelMonths: [], generatedAt: date)
    }

    var isEmpty: Bool {
        typicalSeat == nil && topAirlines.isEmpty && topHotelBrands.isEmpty
            && preferredCabin == nil && frequentCities.isEmpty
            && spendByCategory.isEmpty && typicalBookingLeadDays == nil
            && typicalTripDurationDays == nil && travelCadenceDays == nil
            && peakTravelMonths.isEmpty
    }

    /// Plain-text summary for IRIS's system instructions. Empty when nothing learned
    /// (so the persona stays lean for new users), matching IRISContext's behavior.
    ///
    /// Claims are gated and annotated by sample size so IRIS hedges appropriately
    /// instead of over-asserting a "preference" inferred from a single data point:
    /// ranked lists drop values seen only once, and each surviving value carries its
    /// observation count (e.g. "AA (3×)"). This keeps the learned profile honest.
    func summaryForPrompt() -> String {
        guard !isEmpty else { return "" }
        var lines: [String] = []

        // Only surface a seat preference once it's been seen ≥2 times (matches the
        // seat-nudge gate) so a lone boarding pass doesn't become a "typical seat".
        if let seat = typicalSeat, seat.column != .unknown, seat.sampleSize >= 2 {
            let strength = seat.confidence >= 0.75 ? "usually" : "often"
            lines.append("• Typical seat: \(seat.displayName) (\(strength), \(seat.sampleSize)×)")
        }
        if let airlines = rankedLine(topAirlines, limit: 3) {
            lines.append("• Preferred airlines: \(airlines)")
        }
        if let cabin = preferredCabin {
            lines.append("• Usual cabin: \(cabin)")
        }
        if let hotels = rankedLine(topHotelBrands, limit: 3) {
            lines.append("• Preferred hotels: \(hotels)")
        }
        // Cities include planned/known trips (an explicit, strong signal), so a
        // single occurrence is meaningful here — annotate but don't suppress.
        if !frequentCities.isEmpty {
            let parts = frequentCities.prefix(4).map { annotate($0.value, count: $0.count) }
            lines.append("• Frequent places: \(parts.joined(separator: ", "))")
        }
        // Spend needs ≥2 charges to be a "typical" figure; below that it's just one
        // receipt. Median-based (see TravelProfileEngine), so it resists outliers.
        let spendReliable = spendByCategory.filter { $0.count >= 2 }
        if !spendReliable.isEmpty {
            let top = spendReliable.sorted { $0.average > $1.average }.prefix(3)
            let parts = top.map { "\($0.category) ~\(Int($0.average.rounded())) \($0.currency) (\($0.count)×)" }
            lines.append("• Typical spend: \(parts.joined(separator: ", "))")
        }
        if let lead = typicalBookingLeadDays {
            lines.append("• Usually books ~\(lead) days ahead")
        }
        if let dur = typicalTripDurationDays {
            lines.append("• Typical trip length: ~\(dur) day\(dur == 1 ? "" : "s")")
        }
        if let cadence = travelCadenceDays {
            lines.append("• Travels roughly every \(Self.humanInterval(cadence))")
        }
        if !peakTravelMonths.isEmpty {
            lines.append("• Travels most in: \(peakTravelMonths.joined(separator: ", "))")
        }

        guard !lines.isEmpty else { return "" }
        return "Learned traveler profile (inferred from past behavior; use to personalize, confirm before acting):\n"
            + lines.joined(separator: "\n")
    }

    /// Renders a ranked list for the prompt, dropping values seen only once (so a
    /// single flight/stay doesn't read as a "preferred" brand) and annotating each
    /// survivor with its observation count. Returns nil when nothing clears the bar.
    private func rankedLine(_ values: [WeightedValue], limit: Int) -> String? {
        let strong = values.filter { $0.count >= 2 }.prefix(limit)
        guard !strong.isEmpty else { return nil }
        return strong.map { annotate($0.value, count: $0.count) }.joined(separator: ", ")
    }

    /// "AA" + count → "AA (3×)". Count ≤1 renders bare.
    private func annotate(_ value: String, count: Int) -> String {
        count > 1 ? "\(value) (\(count)×)" : value
    }

    /// Renders a day count as a human cadence ("3 weeks", "2 months", "10 days").
    static func humanInterval(_ days: Int) -> String {
        switch days {
        case ..<14:  return "\(days) day\(days == 1 ? "" : "s")"
        case 14..<60: let w = Int((Double(days) / 7).rounded()); return "\(w) week\(w == 1 ? "" : "s")"
        default:     let m = Int((Double(days) / 30).rounded()); return "\(m) month\(m == 1 ? "" : "s")"
        }
    }
}
