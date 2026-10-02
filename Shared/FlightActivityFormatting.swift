// File: Shared/FlightActivityFormatting.swift
//
// The rules behind the flight Live Activity's text, kept out of the SwiftUI
// views so the app's tests can pin them: which zone a time is shown in, the
// "+1" on a red-eye's arrival, when the compact island swaps its countdown for
// the gate, and how an unknown gate or seat reads.
//
// Compiled into both the app and the widget extension. Inputs are plain
// values (dates, zones, strings), never the activity types, and the enum is
// `nonisolated`, so it works the same in the widget (no default isolation) and
// in the app (MainActor default).

import Foundation

nonisolated enum FlightActivityFormatting {

    /// What an unknown gate, terminal, seat or time reads as. Never a guess.
    static let unknown = "—"

    /// How long before departure the compact island trades its countdown for
    /// "Gate C22": the last stretch is when the traveler is walking to it.
    static let gateFocusWindow: TimeInterval = 45 * 60

    /// How far ahead of departure the minimal ring starts filling. Matches
    /// `FlightLiveActivityService.startWindow`, the earliest a card exists.
    static let ringWindow: TimeInterval = 4 * 3600

    // MARK: - Values

    /// A gate, terminal or seat ready to show, or "—" when it isn't known.
    /// Placeholders some sources store ("-", "TBD") count as unknown.
    static func display(_ value: String?) -> String {
        knownValue(value) ?? unknown
    }

    /// The value when it's real, nil when it's empty or a placeholder.
    static func knownValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed != unknown, trimmed != "-",
              trimmed.uppercased() != "TBD" else { return nil }
        return trimmed
    }

    // MARK: - Time zones and times

    /// The airport's zone from its IANA identifier. An unknown airport falls
    /// back to the device's zone, the same fallback the app uses everywhere
    /// (`AppDateFormatters.airportTimeZone`), so a time is never blank.
    static func timeZone(identifier: String?) -> TimeZone {
        identifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    /// Short wall-clock time at the airport, following the user's 12/24-hour
    /// setting ("9:05 AM" or "09:05").
    static func time(_ date: Date, in zone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = locale.calendar
        calendar.timeZone = zone
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                               locale: locale, calendar: calendar, timeZone: zone))
    }

    /// Calendar days between the departure date at the origin and the arrival
    /// date at the destination: +1 for an overnight flight, −1 for a hop west
    /// across the date line (Tokyo → Honolulu lands "yesterday").
    static func arrivalDayOffset(departure: Date, in departureZone: TimeZone,
                                 arrival: Date, in arrivalZone: TimeZone) -> Int {
        var departureCalendar = Calendar(identifier: .gregorian)
        departureCalendar.timeZone = departureZone
        var arrivalCalendar = Calendar(identifier: .gregorian)
        arrivalCalendar.timeZone = arrivalZone

        // Compare the two local dates as plain calendar days in one fixed zone,
        // so a DST change on either side can't shift the count.
        var reference = Calendar(identifier: .gregorian)
        reference.timeZone = TimeZone(secondsFromGMT: 0) ?? departureZone
        let departureDay = departureCalendar.dateComponents([.year, .month, .day], from: departure)
        let arrivalDay = arrivalCalendar.dateComponents([.year, .month, .day], from: arrival)
        guard let start = reference.date(from: departureDay),
              let end = reference.date(from: arrivalDay) else { return 0 }
        return reference.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// "+1", "−1" (true minus sign) or nil on the same day.
    static func dayOffsetLabel(_ offset: Int) -> String? {
        if offset > 0 { return "+\(offset)" }
        if offset < 0 { return "\u{2212}\(-offset)" }
        return nil
    }

    // MARK: - Island behaviour

    /// True when the compact trailing view should show the gate instead of the
    /// countdown: the gate is known and departure is 45 minutes away or less.
    static func showsGateInCompact(gate: String?, departure: Date, now: Date) -> Bool {
        guard knownValue(gate) != nil else { return false }
        return departure.timeIntervalSince(now) <= gateFocusWindow
    }

    /// A countdown interval ending at departure that is never inverted. A
    /// `ClosedRange` whose lower bound is after its upper bound traps, and a
    /// card rendered after departure would otherwise build exactly that.
    static func countdownRange(to departure: Date, now: Date) -> ClosedRange<Date> {
        min(now, departure)...departure
    }

    /// The minimal ring's interval: it fills over the four hours before
    /// departure, the whole time a card can be on screen before the flight.
    static func ringRange(to departure: Date) -> ClosedRange<Date> {
        departure.addingTimeInterval(-ringWindow)...departure
    }

    /// Share of the scheduled block time flown at `now`, 0 before departure and
    /// 1 after arrival. With no arrival time it stays at 0 rather than guess.
    static func routeProgress(departure: Date, arrival: Date?, now: Date) -> Double {
        guard let arrival, arrival > departure else { return 0 }
        let fraction = now.timeIntervalSince(departure) / arrival.timeIntervalSince(departure)
        return min(max(fraction, 0), 1)
    }

    // MARK: - VoiceOver

    /// A code VoiceOver reads letter by letter ("L A S"), for an airport whose
    /// city name the app doesn't know. Read as a word, "LAS" sounds like "lass".
    static func spelledCode(_ code: String) -> String {
        let letters = code.uppercased().filter { !$0.isWhitespace }
        return letters.isEmpty ? "unknown airport" : letters.map(String.init).joined(separator: " ")
    }
}
