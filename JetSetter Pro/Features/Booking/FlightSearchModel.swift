// File: Features/Booking/FlightSearchModel.swift

import Foundation

// MARK: - Trip Type

/// Whether the flight search is round-trip (depart + return) or one-way.
enum TripType: String, CaseIterable, Identifiable {
    case roundTrip
    case oneWay

    var id: String { rawValue }

    /// Human-readable label for the segmented picker.
    var label: String {
        switch self {
        case .roundTrip: return "Round Trip"
        case .oneWay:    return "One Way"
        }
    }
}

// MARK: - Flight Search Parameters

/// Parameters the user fills in on the flight search form. These are turned into
/// a pre-filled search URL for a flight site (see `FlightBookingProvider`); no
/// flight data is fetched or stored — the site completes the booking.
struct FlightSearchParams {
    var origin: String = ""
    var destination: String = ""
    var departDate: Date = Date()
    var returnDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    var adults: Int = 1
    var tripType: TripType = .roundTrip

    /// Depart date formatted as yyyy-MM-dd — the format flight sites expect.
    /// Reuses the shared date-only formatter defined in `BookingModel`.
    var departDateString: String {
        ISO8601DateFormatter.expediaDate.string(from: departDate)
    }

    /// Return date formatted as yyyy-MM-dd.
    var returnDateString: String {
        ISO8601DateFormatter.expediaDate.string(from: returnDate)
    }

    /// Origin as an upper-cased, whitespace-trimmed IATA code.
    var originCode: String { Self.normalize(origin) }

    /// Destination as an upper-cased, whitespace-trimmed IATA code.
    var destinationCode: String { Self.normalize(destination) }

    private static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

// MARK: - Flight Booking Provider

/// A flight site the app can hand off to. Each case knows how to build a
/// pre-filled deep-link search URL from `FlightSearchParams`. This is the
/// extension seam — add another case to support another site.
enum FlightBookingProvider {
    case kayak

    /// Builds a pre-filled flight-search URL for this provider, or `nil` if the
    /// parameters can't form a valid URL (e.g. a missing airport code).
    func deepLinkURL(for params: FlightSearchParams) -> URL? {
        switch self {
        case .kayak:
            return Self.kayakURL(for: params)
        }
    }

    // MARK: - Kayak

    /// Kayak encodes the search in the URL *path*, e.g.
    ///   Round trip: https://www.kayak.com/flights/JFK-LAX/2026-09-10/2026-09-17?adults=2
    ///   One way:    https://www.kayak.com/flights/JFK-LAX/2026-09-10?adults=2
    private static func kayakURL(for params: FlightSearchParams) -> URL? {
        let origin = params.originCode
        let destination = params.destinationCode
        guard !origin.isEmpty, !destination.isEmpty else { return nil }

        // Path: /flights/<ORIGIN>-<DEST>/<depart>[/<return>]
        var pathSegments = ["flights", "\(origin)-\(destination)", params.departDateString]
        if params.tripType == .roundTrip {
            pathSegments.append(params.returnDateString)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.kayak.com"
        components.path = "/" + pathSegments.joined(separator: "/")
        components.queryItems = [
            URLQueryItem(name: "adults", value: String(max(1, params.adults)))
        ]

        return components.url
    }
}
