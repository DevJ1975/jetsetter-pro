// File: Features/Booking/BookingModel.swift

import Foundation

// MARK: - Hotel Search Parameters

/// Parameters the user fills in on the search form.
struct HotelSearchParams {
    var destination: String = ""
    /// Resolved from `destination` by BookingViewModel via the Rapid Geography
    /// region search before an availability request. Empty until resolved (or
    /// when resolution fails, in which case the raw destination is sent instead).
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

    /// Number of nights between check-in and check-out.
    /// Normalizes both dates to the start of day so the delta is a stable
    /// whole-day count regardless of the time-of-day carried by the Date
    /// timestamps or a DST transition in the device time zone.
    var numberOfNights: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: checkInDate)
        let end = calendar.startOfDay(for: checkOutDate)
        return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
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

    /// The cheapest nightly cost across all rooms and rates.
    ///
    /// Numeric values are only comparable within a single currency, so we
    /// pick the min within each currency and then choose the winning cost by
    /// keeping the value and its own currency together. This prevents pairing
    /// a numerically-small amount in one currency (e.g. JPY) with a different
    /// currency label taken from an unrelated rate.
    private var lowestNightlyCost: RateCost? {
        rooms
            .flatMap { $0.rates }
            .compactMap { $0.nightlyCost }
            .min { lhs, rhs in
                (Double(lhs.value) ?? .greatestFiniteMagnitude)
                    < (Double(rhs.value) ?? .greatestFiniteMagnitude)
            }
    }

    /// Returns the lowest nightly rate value across all rooms and rates.
    var lowestNightlyRate: Double? {
        lowestNightlyCost.flatMap { Double($0.value) }
    }

    /// Currency of the same rate that produced `lowestNightlyRate`, so the
    /// displayed value and its currency label always match.
    var lowestRateCurrency: String {
        lowestNightlyCost?.currency ?? "USD"
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

    /// Formatted nightly price string for display (e.g. "$250.00")
    var formattedNightlyPrice: String {
        CurrencyFormatting.string(from: nightlyCost)
    }

    /// Formatted total price string for display
    var formattedTotalPrice: String {
        CurrencyFormatting.string(from: inclusiveTotal)
    }
}

// MARK: - Currency Formatting

/// Locale-aware money formatting for hotel prices.
///
/// The API delivers amounts as strings paired with an ISO currency code, so we
/// parse to `Decimal` (no binary-floating-point rounding of cents) and render
/// with the currency style, which yields a proper symbol (e.g. "$462.50")
/// instead of the raw ISO code and never silently drops fractional units.
enum CurrencyFormatting {
    /// Formats a `RateCost` (value + ISO currency code) as a localized price.
    /// Returns "N/A" when the cost is missing or the value can't be parsed.
    static func string(from cost: RateCost?) -> String {
        guard let cost, let decimal = Decimal(string: cost.value) else { return "N/A" }
        return string(amount: decimal, currencyCode: cost.currency)
    }

    /// Formats a numeric amount with an ISO currency code as a localized price.
    static func string(amount: Decimal, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode))
    }

    /// Convenience for a `Double` amount (e.g. the precomputed lowest rate).
    static func string(amount: Double, currencyCode: String) -> String {
        string(amount: Decimal(amount), currencyCode: currencyCode)
    }
}

// MARK: - Rate Cost

struct RateCost: Codable {
    let value: String
    let currency: String
}

// MARK: - Expedia Region (Geography region search)

/// One region returned by the Rapid Geography `/v3/regions` search. We only
/// need the `id` to scope an availability search; the endpoint returns many
/// more fields (name, type, coordinates) that we intentionally ignore here.
struct ExpediaRegion: Decodable {
    let id: String
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
