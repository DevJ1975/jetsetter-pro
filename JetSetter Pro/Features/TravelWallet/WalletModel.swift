// File: Features/TravelWallet/WalletModel.swift

import Foundation

// MARK: - WalletItemType

enum WalletItemType: String, Codable, CaseIterable {
    case boardingPass     = "boarding_pass"
    case hotelReservation = "hotel_reservation"
    case carRental        = "car_rental"
    case eventTicket      = "event_ticket"
    case travelInsurance  = "travel_insurance"

    var displayName: String {
        switch self {
        case .boardingPass:     return "Boarding Pass"
        case .hotelReservation: return "Hotel Reservation"
        case .carRental:        return "Car Rental"
        case .eventTicket:      return "Event Ticket"
        case .travelInsurance:  return "Travel Insurance"
        }
    }

    var systemImage: String {
        switch self {
        case .boardingPass:     return "airplane.departure"
        case .hotelReservation: return "building.2.fill"
        case .carRental:        return "car.fill"
        case .eventTicket:      return "ticket.fill"
        case .travelInsurance:  return "shield.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .boardingPass:     return "#0066CC"
        case .hotelReservation: return "#0A7A5E"
        case .carRental:        return "#C8860A"
        case .eventTicket:      return "#7B3FBF"
        case .travelInsurance:  return "#CC3B1E"
        }
    }
}

// MARK: - WalletItemStatus

enum WalletItemStatus: String, Codable {
    case upcoming  = "upcoming"
    case active    = "active"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .upcoming:  return "Upcoming"
        case .active:    return "Active"
        case .completed: return "Completed"
        }
    }

    var colorHex: String {
        switch self {
        case .upcoming:  return "#0066CC"
        case .active:    return "#0A7A5E"
        case .completed: return "#8B92A8"
        }
    }
}

// MARK: - WalletItem

/// A single document in the Travel Wallet, mirroring the `wallet_items` Supabase table:
///   id uuid, user_id uuid, trip_id uuid?, item_type text, title text,
///   confirmation_number text?, date timestamptz, raw_data jsonb, created_at timestamptz
struct WalletItem: Identifiable, Codable, Equatable {
    let id: UUID
    var tripId: UUID?
    var itemType: WalletItemType
    var title: String
    var confirmationNumber: String?
    var date: Date
    /// Flexible key-value store for type-specific fields (airline, seat, hotel address, etc.)
    var rawData: [String: String]
    var createdAt: Date

    // MARK: Computed Status — derived from date/rawData, not persisted
    var status: WalletItemStatus {
        let now = Date()
        // Use end_date from rawData if available, otherwise fall back to the item date
        let endDate = rawData["end_date"].flatMap { isoFormatter.date(from: $0) } ?? date
        if endDate < now    { return .completed }
        if date <= now      { return .active }
        return .upcoming
    }

    // MARK: Boarding Pass Helpers
    var airline: String?          { rawData["airline"] }
    var flightNumber: String?     { rawData["flight_number"] }
    var departureAirport: String? { rawData["departure_airport"] }
    var arrivalAirport: String?   { rawData["arrival_airport"] }
    var seatNumber: String?       { rawData["seat_number"] }
    var gate: String?             { rawData["gate"] }
    var terminal: String?         { rawData["terminal"] }
    var iataCode: String?         { rawData["iata_code"] }

    // MARK: Hotel Helpers
    var hotelAddress: String?     { rawData["hotel_address"] }
    var checkInDateString: String? { rawData["check_in_date"] }
    var checkOutDateString: String? { rawData["check_out_date"] }

    // MARK: Car Rental Helpers
    var rentalCompany: String?    { rawData["rental_company"] }
    var pickupLocation: String?   { rawData["pickup_location"] }
    var vehicleClass: String?     { rawData["vehicle_class"] }

    // MARK: Insurance Helpers
    var policyNumber: String?     { rawData["policy_number"] }
    var provider: String?         { rawData["provider"] }
    var coverageType: String?     { rawData["coverage_type"] }

    // MARK: Event Helpers
    var venue: String?            { rawData["venue"] }
    var eventLocation: String?    { rawData["event_location"] }

    init(
        id: UUID = UUID(),
        tripId: UUID? = nil,
        itemType: WalletItemType,
        title: String,
        confirmationNumber: String? = nil,
        date: Date,
        rawData: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tripId = tripId
        self.itemType = itemType
        self.title = title
        self.confirmationNumber = confirmationNumber
        self.date = date
        self.rawData = rawData
        self.createdAt = createdAt
    }

    // MARK: Coding Keys — match Supabase snake_case column names
    enum CodingKeys: String, CodingKey {
        case id
        case tripId             = "trip_id"
        case itemType           = "item_type"
        case title
        case confirmationNumber = "confirmation_number"
        case date
        case rawData            = "raw_data"
        case createdAt          = "created_at"
    }
}

// Private ISO8601 formatter for status computation
private let isoFormatter = ISO8601DateFormatter()

// MARK: - Grouping Helper

extension Array where Element == WalletItem {
    /// Groups items by trip ID. Items with no trip ID are grouped under `nil`.
    var groupedByTrip: [(tripId: UUID?, items: [WalletItem])] {
        var dict: [UUID?: [WalletItem]] = [:]
        for item in self {
            dict[item.tripId, default: []].append(item)
        }
        // Upcoming/active trips first, then nil, then completed
        let sorted = dict.keys.sorted { keyA, keyB in
            let aHasActive = dict[keyA]!.contains { $0.status != .completed }
            let bHasActive = dict[keyB]!.contains { $0.status != .completed }
            if aHasActive != bHasActive { return aHasActive }
            return false
        }
        return sorted.map { (tripId: $0, items: dict[$0]!) }
    }
}

// MARK: - Sample Data

extension WalletItem {
    static let sampleBoardingPass = WalletItem(
        itemType: .boardingPass,
        title: "JL 006 · NRT → LAX",
        confirmationNumber: "JLXRAY",
        date: Date().addingTimeInterval(2 * 86_400),
        rawData: [
            "airline": "Japan Airlines",
            "flight_number": "JL006",
            "iata_code": "JL",
            "departure_airport": "NRT",
            "arrival_airport": "LAX",
            "seat_number": "14A",
            "gate": "62",
            "terminal": "2"
        ]
    )

    static let sampleHotel = WalletItem(
        itemType: .hotelReservation,
        title: "Park Hyatt Tokyo",
        confirmationNumber: "EXP-2026-45921",
        date: Date().addingTimeInterval(86_400),
        rawData: [
            "hotel_address": "3-7-1-2 Nishishinjuku, Tokyo",
            "check_in_date": isoFormatter.string(from: Date().addingTimeInterval(86_400)),
            "check_out_date": isoFormatter.string(from: Date().addingTimeInterval(4 * 86_400)),
            "end_date": isoFormatter.string(from: Date().addingTimeInterval(4 * 86_400))
        ]
    )

    static let sampleCar = WalletItem(
        itemType: .carRental,
        title: "Hertz — Tokyo Haneda",
        confirmationNumber: "HZ-9921-TKY",
        date: Date().addingTimeInterval(86_400),
        rawData: [
            "rental_company": "Hertz",
            "pickup_location": "HND Terminal 3",
            "vehicle_class": "Compact SUV",
            "end_date": isoFormatter.string(from: Date().addingTimeInterval(4 * 86_400))
        ]
    )
}
