// File: Features/Booking/BookingModel.swift
//
// Hotel search is a hand-off: the form builds a pre-filled search on a hotel
// site (Kayak) and opens it in-app, the same way flights work. Nearby hotels
// for browsing come from MapKit. No partner API, no key, no booking backend.

import Foundation
import CoreLocation
import MapKit

// MARK: - Hotel Search Parameters

/// Parameters the user fills in on the search form.
struct HotelSearchParams {
    var destination: String = ""
    var checkInDate: Date = Date()
    var checkOutDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var adults: Int = 1
    var rooms: Int = 1

    var checkInString: String  { ISO8601DateFormatter.dateOnly.string(from: checkInDate) }
    var checkOutString: String { ISO8601DateFormatter.dateOnly.string(from: checkOutDate) }

    /// Number of nights between check-in and check-out, as whole calendar days.
    var numberOfNights: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: checkInDate)
        let end = calendar.startOfDay(for: checkOutDate)
        return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
    }
}

// MARK: - Hotel Booking Provider

/// A hotel site the app can hand off to, pre-filled from `HotelSearchParams`.
enum HotelBookingProvider {
    case kayak

    var displayName: String {
        switch self {
        case .kayak: return "Kayak"
        }
    }

    /// Kayak encodes the search in the URL path:
    ///   https://www.kayak.com/hotels/Tokyo/2026-09-20/2026-09-23/2adults
    func deepLinkURL(for params: HotelSearchParams) -> URL? {
        let destination = params.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.kayak.com"
        components.path = "/hotels/\(destination)/\(params.checkInString)/\(params.checkOutString)/\(max(1, params.adults))adults"
        return components.url
    }
}

// MARK: - Hotel Place (MapKit)

/// A hotel near the destination, from Apple Maps.
struct HotelPlace: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let phoneNumber: String?
    let websiteURL: URL?

    var formattedDistance: String {
        Measurement(value: distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// The hotel's own site when Apple Maps knows it, otherwise the place in Apple Maps.
    var linkURL: URL? {
        if let websiteURL { return websiteURL }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q",  value: name),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)")
        ]
        return components?.url
    }
}

// MARK: - Date Formatter Helper

extension ISO8601DateFormatter {
    /// Date-only formatter (yyyy-MM-dd) for booking-site URLs.
    static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - Sample Data (Previews)

extension HotelPlace {
    static let samples: [HotelPlace] = [
        HotelPlace(id: "1", name: "Park Hyatt Tokyo", address: "3-7-1-2 Nishishinjuku, Shinjuku City", coordinate: CLLocationCoordinate2D(latitude: 35.6857, longitude: 139.6905), distanceMeters: 900, phoneNumber: nil, websiteURL: URL(string: "https://www.hyatt.com")),
        HotelPlace(id: "2", name: "Hotel Gracery Shinjuku", address: "1-19-1 Kabukicho, Shinjuku City", coordinate: CLLocationCoordinate2D(latitude: 35.6952, longitude: 139.7016), distanceMeters: 1_400, phoneNumber: nil, websiteURL: nil)
    ]
}
