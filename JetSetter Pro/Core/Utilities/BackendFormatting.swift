// File: Core/Utilities/BackendFormatting.swift
//
// Pure helpers for turning backend strings into things a traveler can read.
// Three jobs, each with a past defect it exists to prevent:
//
//  * `BackendDates` converts the contract's zone-less airport wall-clock times
//    ("2026-11-02T09:05:00") into absolute `Date`s using the AIRPORT's zone. A
//    09:05 Las Vegas departure rendered in an Atlanta traveler's device zone
//    reads 12:05, which is how a red-eye once showed the wrong arrival day.
//  * `BackendMoney` keeps amounts as decimal strings end to end and formats with
//    `Decimal`, so JPY (0 digits) and KWD (3 digits) come out right and
//    "245.3" and "245.30" compare equal when checking for a price change.
//  * `BackendDuration` reads ISO-8601 durations ("PT4H10M").
//
// Everything here is `nonisolated` so the networking actor, the sync code and
// the tests can all call it without hopping to the main actor.

import Foundation

// MARK: - Dates

nonisolated enum BackendDates {

    /// A calendar date and clock time with no zone attached.
    struct WallClock: Equatable, Sendable {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
        var second: Int

        var components: DateComponents {
            DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        }
    }

    private static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static var utc: TimeZone { TimeZone(secondsFromGMT: 0) ?? .gmt }

    // MARK: Wall-clock parsing

    /// Reads "2026-11-02T09:05:00" (also "2026-11-02 09:05", fractional seconds,
    /// or a date alone). Any zone suffix is ignored: this reads the digits the
    /// airport clock shows, which is exactly what the contract's local times mean.
    static func wallClock(_ raw: String) -> WallClock? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = text.firstIndex(where: { $0 == "T" || $0 == " " })
        let datePart = separator.map { String(text[..<$0]) } ?? text

        let dateFields = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard dateFields.count == 3,
              let year = Int(dateFields[0]), let month = Int(dateFields[1]), let day = Int(dateFields[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        var hour = 0, minute = 0, second = 0
        if let separator {
            var timePart = String(text[text.index(after: separator)...])
            if let cut = timePart.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
                timePart = String(timePart[..<cut])
            }
            if let dot = timePart.firstIndex(of: ".") { timePart = String(timePart[..<dot]) }
            let fields = timePart.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count >= 2, let h = Int(fields[0]), let m = Int(fields[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            hour = h
            minute = m
            if fields.count >= 3 {
                guard let s = Int(fields[2]), (0...60).contains(s) else { return nil }
                second = s
            }
        }
        return WallClock(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    /// The absolute instant at which the clock in `zone` shows `raw`.
    ///
    /// DST: a wall time inside a spring-forward gap does not exist, and
    /// `Calendar` moves it to the next valid minute; one inside a fall-back
    /// overlap happens twice and `Calendar` picks the first. Both are rare for
    /// real departures and are the same choices the rest of the app makes.
    static func instant(_ raw: String, in zone: TimeZone) -> Date? {
        guard let clock = wallClock(raw) else { return nil }
        return gregorian(in: zone).date(from: clock.components)
    }

    /// How many calendar days later the arrival's local date is than the
    /// departure's local date: 1 for a red-eye ("+1"), -1 for an eastbound
    /// date-line crossing that lands "yesterday" ("-1"). Computed from the two
    /// local dates alone, so it needs no zone and survives DST.
    static func dayOffset(departing: String, arriving: String) -> Int? {
        guard let from = wallClock(departing), let to = wallClock(arriving) else { return nil }
        let calendar = gregorian(in: utc)
        guard let start = calendar.date(from: DateComponents(year: from.year, month: from.month, day: from.day)),
              let end = calendar.date(from: DateComponents(year: to.year, month: to.month, day: to.day)) else { return nil }
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    // MARK: Timestamps

    /// Reads a server timestamp ("2026-11-02T14:05:00Z", with or without
    /// microseconds, or with a numeric offset). A value with no zone is UTC.
    static func parseTimestamp(_ raw: String) -> Date? {
        guard let clock = wallClock(raw) else { return nil }
        let offset = utcOffsetSeconds(in: raw) ?? 0
        let zone = TimeZone(secondsFromGMT: offset) ?? utc
        return gregorian(in: zone).date(from: clock.components)
    }

    /// The numeric offset at the end of a timestamp ("+05:30" -> 19800), or nil
    /// for "Z" or no suffix.
    private static func utcOffsetSeconds(in raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tIndex = text.firstIndex(where: { $0 == "T" || $0 == " " }) else { return nil }
        let timePart = text[text.index(after: tIndex)...]
        guard let signIndex = timePart.lastIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        let sign = timePart[signIndex] == "-" ? -1 : 1
        let digits = timePart[timePart.index(after: signIndex)...].filter(\.isNumber)
        guard digits.count == 2 || digits.count == 4,
              let hours = Int(digits.prefix(2)) else { return nil }
        let minutes = digits.count == 4 ? (Int(digits.suffix(2)) ?? 0) : 0
        return sign * (hours * 3_600 + minutes * 60)
    }

    // MARK: Date-only strings

    /// "2026-11-02" for a date chosen on the device calendar. The search form's
    /// pickers produce device-calendar days, and the backend wants exactly that
    /// day as typed, so this uses the device calendar on purpose.
    static func dateOnlyString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    /// Parses "1990-12-10" into a device-calendar date at local noon, which is
    /// safe from DST edges when it is shown or compared again.
    static func dateOnly(_ raw: String, calendar: Calendar = .current) -> Date? {
        guard let clock = wallClock(raw) else { return nil }
        var components = clock.components
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }
}

// MARK: - Money

nonisolated enum BackendMoney {

    /// Parses a contract amount ("245.30"). Always uses the POSIX locale: the
    /// wire format is "." decimal regardless of the phone's region.
    static func decimal(_ amount: String) -> Decimal? {
        Decimal(string: amount.trimmingCharacters(in: .whitespacesAndNewlines),
                locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The amount as a `Double`, for the few local models that store one
    /// (`BookingCost`). Never used to send money to the server.
    static func double(_ amount: String) -> Double? {
        decimal(amount).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// "$245.30", "¥24,530", "KWD 12.345": the currency decides the fraction
    /// digits. Returns "—" for an amount that can't be read, never a guess.
    static func display(_ amount: String?, currency: String?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let amount, let value = decimal(amount),
              let currency = currency?.trimmingCharacters(in: .whitespacesAndNewlines), !currency.isEmpty
        else { return "—" }
        return value.formatted(.currency(code: currency.uppercased()).locale(locale))
    }

    /// Numeric equality, so "245.3" and "245.30" are the same price.
    static func isSameAmount(_ a: String, _ b: String) -> Bool {
        guard let x = decimal(a), let y = decimal(b) else { return a == b }
        return x == y
    }

    /// True when the amount is zero or unreadable.
    static func isZero(_ amount: String?) -> Bool {
        guard let amount, let value = decimal(amount) else { return true }
        return value == 0
    }
}

// MARK: - Duration

nonisolated enum BackendDuration {

    /// Minutes in an ISO-8601 duration: "PT4H10M" -> 250, "P1DT2H" -> 1560.
    /// Seconds are rounded down. Nil for anything that isn't a duration.
    static func minutes(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              raw.hasPrefix("P"), raw.count > 1 else { return nil }
        var total = 0
        var number = ""
        var inTime = false
        var sawUnit = false
        for character in raw.dropFirst() {
            if character == "T" { inTime = true; continue }
            if character.isNumber { number.append(character); continue }
            guard let value = Int(number) else { return nil }
            number = ""
            sawUnit = true
            switch (character, inTime) {
            case ("D", false): total += value * 1_440
            case ("H", true):  total += value * 60
            case ("M", true):  total += value
            case ("S", true):  total += value / 60
            default: return nil
            }
        }
        return (number.isEmpty && sawUnit) ? total : nil
    }

    /// "4h 10m" in the user's language and style. Nil when unreadable.
    static func display(_ raw: String?) -> String? {
        guard let minutes = minutes(raw) else { return nil }
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

// MARK: - Airports

extension BackendDates {

    /// The zone an airport's wall-clock times belong to: the server's IANA
    /// identifier first, then the app's own airport table. Nil when neither
    /// knows, and callers must then decide (display shows the wall clock
    /// as-is; persistence falls back to the device zone, as the rest of the app
    /// does for an unknown airport).
    nonisolated static func zone(for airport: BackendAirport) -> TimeZone? {
        if let identifier = airport.timeZone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identifier.isEmpty, let zone = TimeZone(identifier: identifier) {
            return zone
        }
        return AirportCoordinates.timeZone(for: airport.iataCode)
    }
}
