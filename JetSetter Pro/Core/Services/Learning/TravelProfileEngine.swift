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

    /// Neutral recency half-life in days: a signal this old contributes half the
    /// weight. Used as the default; specific signal kinds override it below.
    static let halfLifeDays: Double = 365

    /// Per-signal half-lives. Some preferences are stickier than others: seat and
    /// cabin habits persist for years, while favored destinations rotate within a
    /// year. Tuning these separately keeps the profile responsive where tastes move
    /// and stable where they don't.
    enum HalfLife {
        static let seat: Double = 730     // ~2 years — seat habits are sticky
        static let cabin: Double = 730    // cabin preference is sticky too
        static let airline: Double = 365  // brand loyalty — medium persistence
        static let hotel: Double = 365
        static let city: Double = 180     // ~6 months — destinations rotate
    }

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

        // ── Trip rhythm ── duration, cadence, seasonality from known trips.
        // Computed up-front so travel cadence can tune the recency half-life below:
        // frequent flyers should adapt to preference shifts fast, while rare
        // travelers keep their (sparse) signal from decaying into noise.
        let rhythm = tripRhythm(trips: trips)
        let airlineHalfLife = adaptiveHalfLife(base: HalfLife.airline, cadenceDays: rhythm.cadenceDays)
        let hotelHalfLife = adaptiveHalfLife(base: HalfLife.hotel, cadenceDays: rhythm.cadenceDays)
        let cityHalfLife = adaptiveHalfLife(base: HalfLife.city, cadenceDays: rhythm.cadenceDays)

        // ── Airlines ── flight signals + boarding-pass airlines + airline loyalty.
        // Values arrive as a mix of IATA codes ("AA") and names ("American Airlines")
        // across three sources; canonicalize so the same carrier accumulates its full
        // weight instead of splitting into several low-confidence entries.
        var airlineEntries: [(String, Date)] = []
        for s in signals where s.kind == .flightFlown {
            if let a = s.attributes["airline"] ?? optionalNonEmpty(s.value) { airlineEntries.append((canonicalAirline(a), s.timestamp)) }
        }
        for s in signals where s.kind == .loyaltyAdded && s.attributes["brandKind"]?.lowercased() == "airline" {
            airlineEntries.append((canonicalAirline(s.value), s.timestamp))
        }
        for bp in boardingPasses {
            if let a = bp.airline { airlineEntries.append((canonicalAirline(a), bp.date)) }
        }
        let topAirlines = weightedRanking(airlineEntries, now: now, halfLifeDays: airlineHalfLife)

        // ── Hotel brands ── hotel loyalty + accommodation expenses (merchant).
        var hotelEntries: [(String, Date)] = []
        for s in signals where s.kind == .loyaltyAdded && s.attributes["brandKind"]?.lowercased() == "hotel" {
            hotelEntries.append((s.value, s.timestamp))
        }
        for e in expenses where e.category == .accommodation {
            hotelEntries.append((normalizeBrand(e.merchant), e.date))
        }
        let topHotels = weightedRanking(hotelEntries, now: now, halfLifeDays: hotelHalfLife)

        // ── Cabin ── recency-weighted plurality cabin hint from flight signals.
        // Requires ≥2 observations so a single flight can't assert a "usual cabin".
        var cabinEntries: [(String, Date)] = []
        for s in signals where s.kind == .flightFlown {
            if let hint = optionalNonEmpty(s.attributes["cabinHint"] ?? "") {
                cabinEntries.append((hint, s.timestamp))
            }
        }
        let preferredCabin = weightedMode(cabinEntries, now: now, minSample: 2, halfLifeDays: HalfLife.cabin)

        // ── Frequent cities ── trip destinations + place signals.
        var cityEntries: [(String, Date)] = trips.map { (canonicalCity($0.destination), $0.startDate) }
        for s in signals where s.kind == .placeVisited { cityEntries.append((canonicalCity(s.value), s.timestamp)) }
        let cities = weightedRanking(cityEntries.filter { !$0.0.isEmpty }, now: now, halfLifeDays: cityHalfLife)

        // ── Spend by category+currency ── averages from expenses.
        let spend = spendStats(from: expenses)

        // ── Booking lead time ── average of recorded leadDays signals, falling back
        // to the gap between when a boarding pass was added (createdAt) and its
        // departure (date). No feature currently emits an explicit `leadDays`
        // attribute, so without this fallback the field would stay nil forever even
        // though the wallet already carries the timestamps needed to infer it.
        var leads = signals.compactMap { s -> Int? in
            guard s.kind == .tripCompleted, let v = s.attributes["leadDays"] else { return nil }
            return Int(v)
        }
        if leads.isEmpty {
            let cal = Calendar.current
            leads = boardingPasses.compactMap { bp -> Int? in
                // Only trust a plausible lead: the pass must have been added before
                // departure. Passes imported at/after departure (historical backfill)
                // yield 0 or negative and are dropped rather than skewing the average.
                let days = cal.dateComponents([.day], from: bp.createdAt, to: bp.date).day ?? 0
                return days > 0 ? days : nil
            }
        }
        let leadDays = leads.isEmpty ? nil : Int((Double(leads.reduce(0, +)) / Double(leads.count)).rounded())

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

        // Attribute a trip to every calendar month it spans, not just its start
        // month, so a Dec 28 → Jan 20 trip counts toward both December and January
        // rather than reading as purely December. Each spanned month contributes one
        // count; longer trips naturally touch more months.
        var monthCounts: [Int: Int] = [:]
        for trip in trips {
            for month in monthsSpanned(from: trip.startDate, to: trip.endDate, calendar: cal) {
                monthCounts[month, default: 0] += 1
            }
        }
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

    static func seatPreference(
        from seats: [(code: String, date: Date)],
        now: Date,
        halfLifeDays: Double = HalfLife.seat
    ) -> SeatPreference? {
        let parsed = seats
            .map { (column: seatColumn($0.code), zone: seatZone($0.code), date: $0.date) }
            .filter { $0.column != .unknown }
        guard !parsed.isEmpty else { return nil }

        var columnWeights: [SeatColumn: Double] = [:]
        var zoneWeights: [SeatZone: Double] = [:]
        var total = 0.0
        for p in parsed {
            let w = recencyWeight(p.date, now: now, halfLifeDays: halfLifeDays)
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

    static func weightedRanking(
        _ entries: [(String, Date)],
        now: Date,
        limit: Int = 5,
        halfLifeDays: Double = TravelProfileEngine.halfLifeDays
    ) -> [WeightedValue] {
        guard !entries.isEmpty else { return [] }
        var weights: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for (raw, date) in entries {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            weights[key, default: 0] += recencyWeight(date, now: now, halfLifeDays: halfLifeDays)
            counts[key, default: 0] += 1
        }
        // Bayesian-style shrinkage: discount each value's recency weight by
        // n/(n+k) so a single very recent observation can't outrank a value seen
        // many times. k≈2 means a value needs a few sightings to reach ~full weight.
        let k = 2.0
        func shrunk(_ v: WeightedValue) -> Double { v.weight * (Double(v.count) / (Double(v.count) + k)) }
        return weights
            .map { WeightedValue(value: $0.key, weight: $0.value, count: counts[$0.key] ?? 0) }
            .sorted { a, b in
                let sa = shrunk(a), sb = shrunk(b)
                return sa != sb ? sa > sb : a.value < b.value   // deterministic tiebreak
            }
            .prefix(limit)
            .map { $0 }
    }

    static func spendStats(from expenses: [Expense]) -> [SpendStat] {
        // Mileage is reimbursement bookkeeping, not a spend preference — exclude it.
        let relevant = expenses.filter { $0.category != .mileage }
        let groups = Dictionary(grouping: relevant) { "\($0.category.displayName)|\($0.currency)" }
        return groups.compactMap { _, items in
            guard let first = items.first, !items.isEmpty else { return nil }
            // Median is robust to a single outlier charge (e.g. one $999 hotel night
            // skewing a 2-charge average). `count` is carried so downstream callers
            // can gate on sample size before trusting the figure (budget-pacing nudge
            // requires count ≥ 3; see IRISTriggers).
            let typical = median(items.map(\.amount))
            return SpendStat(category: first.category.displayName, currency: first.currency,
                             average: typical, count: items.count)
        }
        .sorted { $0.average > $1.average }
    }

    // MARK: - Weighting + normalization

    /// Small tolerance (5 min) for benign clock skew between devices/imports.
    static let clockSkewToleranceSeconds: TimeInterval = 300

    static func recencyWeight(
        _ date: Date,
        now: Date,
        halfLifeDays: Double = TravelProfileEngine.halfLifeDays
    ) -> Double {
        let age = now.timeIntervalSince(date)
        // Signals dated clearly in the future (beyond clock-skew tolerance) are
        // invalid — clamping their age to 0 would hand them the maximum weight and
        // let one bogus timestamp dominate. Treat them as neutral (0) instead.
        guard age >= -clockSkewToleranceSeconds else { return 0 }
        let ageDays = max(0, age / 86_400)
        return pow(0.5, ageDays / halfLifeDays)
    }

    /// Recency-weighted plurality over dated string observations. Returns nil unless
    /// at least `minSample` observations exist — prevents asserting a preference from
    /// a single data point. Deterministic tiebreak (lexicographically smallest).
    static func weightedMode(
        _ entries: [(String, Date)],
        now: Date,
        minSample: Int,
        halfLifeDays: Double = TravelProfileEngine.halfLifeDays
    ) -> String? {
        let cleaned = entries
            .map { ($0.0.trimmingCharacters(in: .whitespacesAndNewlines), $0.1) }
            .filter { !$0.0.isEmpty }
        guard cleaned.count >= minSample else { return nil }
        var weights: [String: Double] = [:]
        for (value, date) in cleaned { weights[value, default: 0] += recencyWeight(date, now: now, halfLifeDays: halfLifeDays) }
        guard let best = weights.max(by: {
            $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key
        }), best.value > 0 else { return nil }
        return best.key
    }

    /// Median of a value set — a central estimate that resists single outliers.
    /// Empty input → 0.
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
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

    // MARK: - Canonicalization

    /// Folds a city/place value to a stable comparison-and-display key so the same
    /// place accumulates its full weight regardless of trailing region, casing, or
    /// diacritics ("São Paulo", "Sao Paulo, Brazil", "SÃO PAULO" → "Sao Paulo").
    /// Case/diacritics are stripped for grouping, then title-cased for a clean label.
    static func canonicalCity(_ s: String) -> String {
        let head = normalizeCity(s)
        guard !head.isEmpty else { return head }
        let folded = head.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        return folded.capitalized(with: Locale(identifier: "en_US_POSIX"))
    }

    /// Canonical IATA airline codes ↔ common names. Sources emit a carrier as a code
    /// ("AA"), a full name ("American Airlines"), or a short name ("American"); all
    /// must map to one key or their weight fragments across separate ranked entries
    /// and none reaches meaningful confidence. Returns the IATA code when recognized,
    /// otherwise a trimmed/case-folded form of the input.
    static func canonicalAirline(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let key = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        // A bare 2-letter token is almost certainly already an IATA code.
        if key.count == 2, key.allSatisfy({ $0.isLetter }), airlineCodeToName[key.uppercased()] != nil {
            return key.uppercased()
        }
        if airlineNameToCode[key] != nil { return airlineNameToCode[key] ?? trimmed }
        // Match on a leading name fragment ("American" → "American Airlines").
        for (name, code) in airlineNameToCode where key == name || name.hasPrefix(key) || key.hasPrefix(name) {
            return code
        }
        return trimmed
    }

    /// A small, high-traffic IATA map. Intentionally not exhaustive — unknown carriers
    /// fall through to their trimmed name, which is still stable across identical inputs.
    static let airlineCodeToName: [String: String] = [
        "AA": "American Airlines", "DL": "Delta Air Lines", "UA": "United Airlines",
        "WN": "Southwest Airlines", "AS": "Alaska Airlines", "B6": "JetBlue Airways",
        "NK": "Spirit Airlines", "F9": "Frontier Airlines", "HA": "Hawaiian Airlines",
        "AC": "Air Canada", "BA": "British Airways", "LH": "Lufthansa",
        "AF": "Air France", "KL": "KLM", "EK": "Emirates", "QR": "Qatar Airways",
        "SQ": "Singapore Airlines", "CX": "Cathay Pacific", "QF": "Qantas",
        "JL": "Japan Airlines", "NH": "All Nippon Airways", "TK": "Turkish Airlines",
        "IB": "Iberia", "VS": "Virgin Atlantic", "EY": "Etihad Airways"
    ]

    /// Case/diacritic-folded name → IATA code, including a few common short names.
    static let airlineNameToCode: [String: String] = {
        var map: [String: String] = [:]
        let fold: (String) -> String = {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive],
                       locale: Locale(identifier: "en_US_POSIX"))
        }
        for (code, name) in airlineCodeToName { map[fold(name)] = code }
        // Colloquial short names travelers (and OCR) frequently produce.
        let shortNames: [String: String] = [
            "american": "AA", "delta": "DL", "united": "UA", "southwest": "WN",
            "alaska": "AS", "jetblue": "B6", "spirit": "NK", "frontier": "F9",
            "hawaiian": "HA", "lufthansa": "LH", "emirates": "EK", "qantas": "QF",
            "iberia": "IB", "ana": "NH", "jal": "JL"
        ]
        for (name, code) in shortNames { map[fold(name)] = code }
        return map
    }()

    // MARK: - Adaptive recency

    /// Tunes a base half-life to the traveler's cadence so the profile adapts at the
    /// pace they actually travel. A frequent flyer (short cadence) should let stale
    /// preferences decay quickly; a rare traveler (long cadence, sparse signal) needs
    /// a longer memory so their few data points aren't diluted to noise. We target
    /// ~3.5× cadence, clamped to [90, base] so we never decay faster than 3 months and
    /// never exceed the sticky per-kind base half-life.
    static func adaptiveHalfLife(base: Double, cadenceDays: Int?) -> Double {
        guard let cadence = cadenceDays, cadence > 0 else { return base }
        let target = Double(cadence) * 3.5
        return min(base, max(90, target))
    }

    // MARK: - Month spans

    /// Every calendar month index (1...12) a trip touches, inclusive of both ends.
    /// A trip spanning a year boundary (e.g. Dec → Jan) contributes both months.
    /// Falls back to the start month if the range is inverted or unresolvable.
    static func monthsSpanned(from start: Date, to end: Date, calendar: Calendar) -> [Int] {
        let startMonth = calendar.component(.month, from: start)
        guard end >= start else { return [startMonth] }
        var months: [Int] = []
        var seen = Set<Int>()
        // Walk month-by-month from the start's month anchor to the end date.
        guard var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) else {
            return [startMonth]
        }
        // Guard the loop against pathological ranges.
        var guardCount = 0
        while cursor <= end, guardCount < 600 {
            let m = calendar.component(.month, from: cursor)
            if seen.insert(m).inserted { months.append(m) }
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }
        return months.isEmpty ? [startMonth] : months
    }
}
