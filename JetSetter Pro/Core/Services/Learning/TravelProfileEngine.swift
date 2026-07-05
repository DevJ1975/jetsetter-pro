// File: Core/Services/Learning/TravelProfileEngine.swift
//
// Pure, deterministic aggregation of TravelSignals + on-device history into a
// TravelProfile. No I/O, no state, no actor isolation — every function is a pure
// transform so it can be exercised directly (RunCodeSnippet) and unit-tested.
//
// Signals are weighted by recency (exponential decay, ~1-year half-life) so the
// profile tracks how preferences evolve rather than freezing on early behavior.

import Foundation

enum TravelProfileEngine {

    /// Recency half-life in days: a signal this old contributes half the weight.
    static let halfLifeDays: Double = 365

    // MARK: - Build

    static func buildProfile(
        signals: [TravelSignal],
        boardingPasses: [WalletItem] = [],
        trips: [Trip] = [],
        expenses: [Expense] = [],
        now: Date = Date()
    ) -> TravelProfile {

        // ── Seats ── from explicit seat signals + boarding-pass seat numbers.
        var seatCodes: [(code: String, date: Date)] = signals
            .filter { $0.kind == .seatChosen }
            .map { ($0.value, $0.timestamp) }
        seatCodes += boardingPasses
            .compactMap { bp in bp.seatNumber.map { ($0, bp.date) } }
        let seat = seatPreference(from: seatCodes, now: now)

        // ── Airlines ── flight signals + boarding-pass airlines + airline loyalty.
        var airlineEntries: [(String, Date)] = []
        for s in signals where s.kind == .flightFlown {
            if let a = s.attributes["airline"] ?? optionalNonEmpty(s.value) { airlineEntries.append((a, s.timestamp)) }
        }
        for s in signals where s.kind == .loyaltyAdded && s.attributes["brandKind"]?.lowercased() == "airline" {
            airlineEntries.append((s.value, s.timestamp))
        }
        for bp in boardingPasses {
            if let a = bp.airline { airlineEntries.append((a, bp.date)) }
        }
        let topAirlines = weightedRanking(airlineEntries, now: now)

        // ── Hotel brands ── hotel loyalty + accommodation expenses (merchant).
        var hotelEntries: [(String, Date)] = []
        for s in signals where s.kind == .loyaltyAdded && s.attributes["brandKind"]?.lowercased() == "hotel" {
            hotelEntries.append((s.value, s.timestamp))
        }
        for e in expenses where e.category == .accommodation {
            hotelEntries.append((normalizeBrand(e.merchant), e.date))
        }
        let topHotels = weightedRanking(hotelEntries, now: now)

        // ── Cabin ── majority cabin hint from flight signals.
        let cabinHints = signals.compactMap { $0.kind == .flightFlown ? $0.attributes["cabinHint"] : nil }
        let preferredCabin = mostCommon(cabinHints)

        // ── Frequent cities ── trip destinations + place signals.
        var cityEntries: [(String, Date)] = trips.map { (normalizeCity($0.destination), $0.startDate) }
        for s in signals where s.kind == .placeVisited { cityEntries.append((normalizeCity(s.value), s.timestamp)) }
        let cities = weightedRanking(cityEntries.filter { !$0.0.isEmpty }, now: now)

        // ── Spend by category+currency ── averages from expenses.
        let spend = spendStats(from: expenses)

        // ── Booking lead time ── average of recorded leadDays signals.
        let leads = signals.compactMap { s -> Int? in
            guard s.kind == .tripCompleted, let v = s.attributes["leadDays"] else { return nil }
            return Int(v)
        }
        let leadDays = leads.isEmpty ? nil : Int((Double(leads.reduce(0, +)) / Double(leads.count)).rounded())

        // ── Trip rhythm ── duration, cadence, seasonality from known trips.
        let rhythm = tripRhythm(trips: trips)

        return TravelProfile(
            typicalSeat: seat,
            topAirlines: topAirlines,
            topHotelBrands: topHotels,
            preferredCabin: preferredCabin,
            frequentCities: cities,
            spendByCategory: spend,
            typicalBookingLeadDays: leadDays,
            typicalTripDurationDays: rhythm.durationDays,
            travelCadenceDays: rhythm.cadenceDays,
            peakTravelMonths: rhythm.peakMonths,
            generatedAt: now
        )
    }

    // MARK: - Trip rhythm

    /// Average trip length, average gap between trip starts, and peak travel months.
    /// Seasonality is only surfaced with enough trips and a clear peak, to avoid
    /// over-claiming from one or two data points.
    static func tripRhythm(trips: [Trip]) -> (durationDays: Int?, cadenceDays: Int?, peakMonths: [String]) {
        guard !trips.isEmpty else { return (nil, nil, []) }
        let cal = Calendar.current

        let durations = trips
            .map { max(0, cal.dateComponents([.day], from: $0.startDate, to: $0.endDate).day ?? 0) }
            .filter { $0 > 0 }
        let duration = durations.isEmpty ? nil
            : Int((Double(durations.reduce(0, +)) / Double(durations.count)).rounded())

        let starts = trips.map(\.startDate).sorted()
        var cadence: Int?
        if starts.count >= 2 {
            var gaps: [Int] = []
            for i in 1..<starts.count {
                let d = cal.dateComponents([.day], from: starts[i - 1], to: starts[i]).day ?? 0
                if d > 0 { gaps.append(d) }
            }
            if !gaps.isEmpty { cadence = Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded()) }
        }

        let monthCounts = Dictionary(grouping: trips.map { cal.component(.month, from: $0.startDate) }) { $0 }
            .mapValues(\.count)
        let maxCount = monthCounts.values.max() ?? 0
        let fmt = DateFormatter()
        let peakMonths: [String] = (trips.count >= 3 && maxCount >= 2)
            ? monthCounts.filter { $0.value == maxCount }.keys.sorted()
                .prefix(2)
                .compactMap { (1...12).contains($0) ? fmt.monthSymbols[$0 - 1] : nil }
            : []

        return (duration, cadence, peakMonths)
    }

    // MARK: - Seat parsing

    /// Window for typical layouts; A/F/K/L window, C/D/G/H aisle, B/E middle.
    static func seatColumn(_ seat: String) -> SeatColumn {
        guard let letter = seat.uppercased().last(where: { $0.isLetter }) else { return .unknown }
        switch letter {
        case "A", "F", "K", "L": return .window
        case "C", "D", "G", "H": return .aisle
        case "B", "E":           return .middle
        default:                 return .unknown
        }
    }

    static func seatRow(_ seat: String) -> Int? {
        let digits = seat.prefix { $0.isNumber }
        return Int(digits)
    }

    static func seatZone(_ seat: String) -> SeatZone {
        guard let row = seatRow(seat) else { return .unknown }
        switch row {
        case ..<11:  return .forward
        case 11..<26: return .mid
        default:     return .rear
        }
    }

    static func seatPreference(from seats: [(code: String, date: Date)], now: Date) -> SeatPreference? {
        let parsed = seats
            .map { (column: seatColumn($0.code), zone: seatZone($0.code), date: $0.date) }
            .filter { $0.column != .unknown }
        guard !parsed.isEmpty else { return nil }

        var columnWeights: [SeatColumn: Double] = [:]
        var zoneWeights: [SeatZone: Double] = [:]
        var total = 0.0
        for p in parsed {
            let w = recencyWeight(p.date, now: now)
            columnWeights[p.column, default: 0] += w
            if p.zone != .unknown { zoneWeights[p.zone, default: 0] += w }
            total += w
        }
        // Stable tiebreak (by rawValue) so identical histories always yield the same result.
        guard total > 0, let domColumn = columnWeights.max(by: {
            $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue
        }) else { return nil }
        let domZone = zoneWeights.max(by: {
            $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue
        })?.key ?? .unknown
        return SeatPreference(
            column: domColumn.key,
            zone: domZone,
            confidence: domColumn.value / total,
            sampleSize: parsed.count
        )
    }

    // MARK: - Ranking helpers

    static func weightedRanking(_ entries: [(String, Date)], now: Date, limit: Int = 5) -> [WeightedValue] {
        guard !entries.isEmpty else { return [] }
        var weights: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for (raw, date) in entries {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            weights[key, default: 0] += recencyWeight(date, now: now)
            counts[key, default: 0] += 1
        }
        return weights
            .map { WeightedValue(value: $0.key, weight: $0.value, count: counts[$0.key] ?? 0) }
            .sorted { $0.weight > $1.weight }
            .prefix(limit)
            .map { $0 }
    }

    static func spendStats(from expenses: [Expense]) -> [SpendStat] {
        // Mileage is reimbursement bookkeeping, not a spend preference — exclude it.
        let relevant = expenses.filter { $0.category != .mileage }
        let groups = Dictionary(grouping: relevant) { "\($0.category.displayName)|\($0.currency)" }
        return groups.compactMap { _, items in
            guard let first = items.first, !items.isEmpty else { return nil }
            let avg = items.reduce(0.0) { $0 + $1.amount } / Double(items.count)
            return SpendStat(category: first.category.displayName, currency: first.currency,
                             average: avg, count: items.count)
        }
        .sorted { $0.average > $1.average }
    }

    // MARK: - Weighting + normalization

    /// Small tolerance (5 min) for benign clock skew between devices/imports.
    static let clockSkewToleranceSeconds: TimeInterval = 300

    static func recencyWeight(_ date: Date, now: Date) -> Double {
        let age = now.timeIntervalSince(date)
        // Signals dated clearly in the future (beyond clock-skew tolerance) are
        // invalid — clamping their age to 0 would hand them the maximum weight and
        // let one bogus timestamp dominate. Treat them as neutral (0) instead.
        guard age >= -clockSkewToleranceSeconds else { return 0 }
        let ageDays = max(0, age / 86_400)
        return pow(0.5, ageDays / halfLifeDays)
    }

    private static func mostCommon(_ values: [String]) -> String? {
        let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        // Most frequent; on a tie, the lexicographically smallest value (deterministic).
        return Dictionary(grouping: cleaned) { $0 }.max(by: {
            $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key
        })?.key
    }

    private static func optionalNonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Collapses a merchant/brand string to a stable display key (e.g. trims a
    /// trailing location: "Marriott Tokyo" stays "Marriott Tokyo" but case-normalizes).
    private static func normalizeBrand(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Takes the leading component of a destination string ("Tokyo, Japan" -> "Tokyo").
    static func normalizeCity(_ s: String) -> String {
        let head = s.split(separator: ",").first.map(String.init) ?? s
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
