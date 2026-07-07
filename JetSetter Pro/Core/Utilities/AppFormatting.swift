// File: Core/Utilities/AppFormatting.swift
//
// Shared formatting and Codable primitives. Previously each view model, store,
// and IRIS tool created its own JSONDecoder/JSONEncoder (with `.iso8601`),
// ISO8601DateFormatter, DateFormatter, and NumberFormatter inline — the same
// setup copy-pasted across dozens of sites. Beyond the duplication, allocating
// these Foundation formatters is genuinely expensive, so re-creating them per
// call is a real perf cost on hot paths. Centralized here so there's a single
// source of truth and each configured instance is created once and reused.
//
// NOTE: only *statically-configured* formatters belong here. Formatters whose
// locale/time zone/format is chosen dynamically at the call site (e.g. an IRIS
// flight time rendered in that flight's origin time zone) intentionally stay
// local — a shared cached instance can't carry per-call configuration.

import Foundation

// MARK: - JSON coding

/// Cached JSON coders configured with the `.iso8601` date strategy used by the
/// app's on-device persistence (trips, bags, expenses, loyalty, IRIS memory,
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
/// parsed/serialized across providers and IRIS tools.
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
