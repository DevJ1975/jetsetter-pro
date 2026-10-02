// File: Core/Utilities/AppFormatting.swift
//
// Shared formatting and Codable primitives. Previously each view model, store,
// and the app tool created its own JSONDecoder/JSONEncoder (with `.iso8601`),
// ISO8601DateFormatter, DateFormatter, and NumberFormatter inline — the same
// setup copy-pasted across dozens of sites. Beyond the duplication, allocating
// these Foundation formatters is genuinely expensive, so re-creating them per
// call is a real perf cost on hot paths. Centralized here so there's a single
// source of truth and each configured instance is created once and reused.
//
// NOTE: the cached `DateFormatter`s here are *statically configured* and
// render in the device's zone. Flight times belong to an airport, not the
// phone, so they go through `AppDateFormatters.airportTime` at the bottom of
// this file, which takes the zone per call.

import Foundation

// MARK: - JSON coding

/// Cached JSON coders configured with the `.iso8601` date strategy used by the
/// app's on-device persistence (trips, bags, expenses, loyalty, the app memory,
/// exchange-rate cache, document vault). Reads and writes MUST use the same
/// strategy, so both live here together.
///
/// This is distinct from `APIClient.decoder` / `APIClient.snakeCaseEncoder`,
/// which additionally apply snake_case key conversion for network payloads.
enum JSONCoding {

    /// Decoder with `.iso8601` date decoding. Reuse instead of allocating a
    /// fresh `JSONDecoder()` and setting the strategy at each call site.
    static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Encoder with `.iso8601` date encoding, matching `iso8601Decoder`.
    static let iso8601Encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - ISO 8601 date formatters

/// Cached `ISO8601DateFormatter` instances for the internet-date-time shapes
/// parsed/serialized across providers and the app tools.
enum ISO8601Formatters {

    /// Standard RFC 3339 / internet date-time, no fractional seconds
    /// (e.g. "2026-07-06T14:30:00Z"). The default `ISO8601DateFormatter()`
    /// configuration — use this instead of allocating one.
    static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Internet date-time including fractional seconds
    /// (e.g. "2026-07-06T14:30:00.123Z"). Some APIs (Amadeus, FlightAware)
    /// emit fractional seconds; parse with this after `internetDateTime` fails.
    static let internetDateTimeFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Date-only (`.withFullDate`, e.g. "2026-07-06"), used for query params
    /// like rental-car pickup/drop-off dates.
    static let fullDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

// MARK: - Display date formatters

/// Cached `DateFormatter` instances for user-facing date/time display in the
/// device's current locale and time zone. Only style-based formatters with no
/// per-call configuration live here (see the file note).
enum AppDateFormatters {

    /// Medium date, no time (e.g. "Jul 6, 2026").
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Medium date with short time (e.g. "Jul 6, 2026 at 2:30 PM").
    static let mediumDateShortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Short time, no date (e.g. "2:30 PM") in the current time zone.
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Airport-local time

// A flight time is a wall-clock time *at an airport*. The cached formatters
// above render in the phone's zone, which is how Siri once told a traveler in
// Atlanta that their 9:05 AM Las Vegas departure left at "12:05 PM". These
// helpers render an absolute instant in the airport's own zone instead.
//
// They use `Date.FormatStyle` rather than a per-zone `DateFormatter` cache:
// the style is a cheap value type that carries its zone, and Foundation keeps
// the expensive ICU formatter behind it cached per configuration, so there's
// no lock-guarded dictionary to maintain. `nonisolated` so background work can
// call them too; nothing here touches main-actor state.
extension AppDateFormatters {

    /// How much of the instant `airportTime` renders. Every style follows the
    /// locale, so a 24-hour user gets "09:05" and a 12-hour user "9:05 AM".
    nonisolated enum AirportTimeStyle: Sendable {
        /// Time only, e.g. "9:05 AM".
        case time
        /// Medium date with short time, e.g. "Sep 14, 2026 at 9:05 AM".
        case dateTime
        /// Weekday and date, no time, e.g. "Mon, Sep 14, 2026".
        case weekdayDate
    }

    /// The zone to render an airport's times in: the airport's own zone when
    /// `AirportCoordinates` knows the code, otherwise the device's zone (the
    /// same fallback the app used before, so an unknown airport never crashes
    /// or blanks a time).
    nonisolated static func airportTimeZone(for iata: String?) -> TimeZone {
        guard let code = iata?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty,
              let zone = AirportCoordinates.timeZone(for: code) else { return .current }
        return zone
    }

    /// Formats `date` as the wall-clock time at the airport `iata`, falling
    /// back to the device zone when the code is unknown or missing.
    nonisolated static func airportTime(
        _ date: Date,
        iata: String?,
        style: AirportTimeStyle = .dateTime,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        airportTime(date, in: airportTimeZone(for: iata), style: style, locale: locale)
    }

    /// Formats `date` in an explicit zone. For callers that already resolved
    /// the zone some other way (a pass that carried its own zone identifier).
    nonisolated static func airportTime(
        _ date: Date,
        in timeZone: TimeZone,
        style: AirportTimeStyle = .dateTime,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        // The calendar's zone decides which *day* the instant falls on, so it
        // must match the format zone or a late-evening departure prints with
        // the wrong date.
        var calendar = locale.calendar
        calendar.timeZone = timeZone
        let format: Date.FormatStyle
        switch style {
        case .time:
            format = Date.FormatStyle(date: .omitted, time: .shortened,
                                      locale: locale, calendar: calendar, timeZone: timeZone)
        case .dateTime:
            format = Date.FormatStyle(date: .abbreviated, time: .shortened,
                                      locale: locale, calendar: calendar, timeZone: timeZone)
        case .weekdayDate:
            format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .weekday(.abbreviated).month(.abbreviated).day().year()
        }
        return date.formatted(format)
    }
}
