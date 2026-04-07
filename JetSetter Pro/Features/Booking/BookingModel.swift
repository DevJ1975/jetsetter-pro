// File: Features/Booking/BookingModel.swift

import Foundation

// MARK: - Hotel Search Parameters

/// Parameters the user fills in on the search form.
struct HotelSearchParams {
    var destination: String = ""
    /// TODO: In production, resolve destination text to an Expedia region_id first.
    var regionID: String = ""
    var checkInDate: Date = Date()
    var checkOutDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var adults: Int = 1
    var rooms: Int = 1
    var currency: String = "USD"

    /// Formatted check-in string required by Expedia API (yyyy-MM-dd)
    var checkInString: String {
        ISO8601DateFormatter.expediaDate.string(from: checkInDate)
    }

    /// Formatted check-out string required by Expedia API (yyyy-MM-dd)
    var checkOutString: String {
        ISO8601DateFormatter.expediaDate.string(from: checkOutDate)
    }

    /// Number of nights between check-in and check-out
    var numberOfNights: Int {
        max(1, Calendar.current.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 1)
    }
}

// MARK: - Hotel Property

/// A hotel property returned by the Expedia availability search.
struct HotelProperty: Identifiable, Codable {
    let propertyId: String
    var name: String? = nil      // Display name e.g. "Four Seasons Hotel"
    let status: String
    let score: Double?
    let rooms: [HotelRoom]

    var id: String { propertyId }

    /// Returns the lowest nightly rate across all rooms and rates
    var lowestNightlyRate: Double? {
        rooms
            .flatMap { $0.rates }
            .compactMap { Double($0.nightlyCost?.value ?? "") }
            .min()
    }

    var lowestRateCurrency: String {
        rooms.first?.rates.first?.nightlyCost?.currency ?? "USD"
    }
}

// MARK: - Hotel Room

struct HotelRoom: Codable {
    let id: String
    let roomName: String?
    let rates: [RoomRate]
}

// MARK: - Room Rate

struct RoomRate: Codable, Identifiable {
    let id: String
    let availableRooms: Int?
    let refundable: Bool?
    let nightlyCost: RateCost?
    let inclusiveTotal: RateCost?

    /// Formatted nightly price string for display (e.g. "$250")
    var formattedNightlyPrice: String {
        guard let cost = nightlyCost, let value = Double(cost.value) else { return "N/A" }
        return "\(cost.currency) \(String(format: "%.0f", value))"
    }

    /// Formatted total price string for display
    var formattedTotalPrice: String {
        guard let cost = inclusiveTotal, let value = Double(cost.value) else { return "N/A" }
        return "\(cost.currency) \(String(format: "%.0f", value))"
    }
}

// MARK: - Rate Cost

struct RateCost: Codable {
    let value: String
    let currency: String
}

// MARK: - Expedia OAuth Token Response

struct ExpediaTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
}

// MARK: - Date Formatter Helper

extension ISO8601DateFormatter {
    /// Date-only formatter for Expedia API parameters (yyyy-MM-dd)
    static let expediaDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - Sample Data (Previews)

extension HotelProperty {
    static let sampleProperties: [HotelProperty] = [
        HotelProperty(
            propertyId: "prop_001",
            status: "available",
            score: 4.8,
            rooms: [
                HotelRoom(
                    id: "room_001",
                    roomName: "Deluxe King Room",
                    rates: [
                        RoomRate(
                            id: "rate_001",
                            availableRooms: 3,
                            refundable: true,
                            nightlyCost: RateCost(value: "420", currency: "USD"),
                            inclusiveTotal: RateCost(value: "462", currency: "USD")
                        )
                    ]
                ),
                HotelRoom(
                    id: "room_002",
                    roomName: "Park View Suite",
                    rates: [
                        RoomRate(
                            id: "rate_002",
                            availableRooms: 1,
                            refundable: false,
                            nightlyCost: RateCost(value: "780", currency: "USD"),
                            inclusiveTotal: RateCost(value: "858", currency: "USD")
                        )
                    ]
                )
            ]
        ),
        HotelProperty(
            propertyId: "prop_002",
            status: "available",
            score: 4.2,
            rooms: [
                HotelRoom(
                    id: "room_003",
                    roomName: "Standard Double",
                    rates: [
                        RoomRate(
                            id: "rate_003",
                            availableRooms: 8,
                            refundable: true,
                            nightlyCost: RateCost(value: "195", currency: "USD"),
                            inclusiveTotal: RateCost(value: "214", currency: "USD")
                        )
                    ]
                )
            ]
        )
    ]
}
