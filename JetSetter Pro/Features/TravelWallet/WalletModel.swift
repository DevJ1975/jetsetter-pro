// File: Features/TravelWallet/WalletModel.swift

import Foundation

// MARK: - WalletItemType

nonisolated enum WalletItemType: String, Codable, CaseIterable {
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

nonisolated enum WalletItemStatus: String, Codable {
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

/// A single document in the Travel Wallet, mirroring the `wallet_items` Firebase table:
///   id uuid, user_id uuid, trip_id uuid?, item_type text, title text,
///   confirmation_number text?, date timestamptz, raw_data jsonb, created_at timestamptz
nonisolated struct WalletItem: Identifiable, Codable, Equatable {
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
        // Prefer an explicit ranged end_date. For time-of-use documents that only
        // carry a single start instant (boarding passes, car pick-ups, event
        // tickets), completing exactly at the start time would collapse the
        // document into the dimmed "Past" section while the traveler still needs
        // it (mid-flight, at the rental counter, entering the venue). Give those a
        // grace window past their start before treating them as completed.
        let endDate = rawData["end_date"].flatMap { makeISOFormatter().date(from: $0) }
            ?? date.addingTimeInterval(timeOfUseGrace)
        if endDate < now    { return .completed }
        if date <= now      { return .active }
        return .upcoming
    }

    /// How long a single-instant document stays "active" past its start time when
    /// no explicit end_date is known. Boarding passes get a wider window (covers a
    /// typical flight plus connection buffer); other single-instant docs a shorter one.
    private var timeOfUseGrace: TimeInterval {
        switch itemType {
        case .boardingPass:            return 6 * 3_600   // ~6h — covers most flights
        case .carRental, .eventTicket: return 4 * 3_600
        case .hotelReservation, .travelInsurance:
            return 0                                       // ranged docs supply end_date
        }
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
    /// Explicit cabin/fare class if the pass carried one (e.g. "Economy").
    /// When absent, callers fall back to a seat-row heuristic (marked as an estimate).
    var cabinClass: String?       { rawData["cabin_class"] }
    /// Boarding group as parsed from a real imported pass, if present.
    var boardingGroup: String?    { rawData["boarding_group"] }
    /// Boarding sequence number as parsed from a real imported pass, if present.
    var boardingSequence: String? { rawData["sequence_number"] }
    /// Raw barcode message from an imported pkpass, if captured. Used to render
    /// the actual scannable code rather than synthesizing one.
    var barcodeMessage: String?   { rawData["barcode_message"] }

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

    // MARK: Coding Keys — match Firebase snake_case column names
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

// Private ISO8601 formatter factory for status computation.
// `nonisolated` so callers from any actor context can use it (the project
// defaults to `@MainActor` isolation, which would otherwise propagate to
// this top-level function and make it unusable from nonisolated contexts
// such as `WalletItem.status`).
private nonisolated func makeISOFormatter() -> ISO8601DateFormatter {
    ISO8601Formatters.internetDateTime
}

// MARK: - Grouping Helper

extension Array where Element == WalletItem {
    /// Groups items by trip ID. Items with no trip ID are grouped under `nil`.
    var groupedByTrip: [(tripId: UUID?, items: [WalletItem])] {
        var dict: [UUID?: [WalletItem]] = [:]
        for item in self {
            dict[item.tripId, default: []].append(item)
        }
        // Ordering rank: groups with a live (upcoming/active) item first,
        // then the unassigned (nil-tripId) group, then all-completed groups.
        func rank(_ key: UUID?) -> Int {
            let items = dict[key] ?? []
            if items.contains(where: { $0.status != .completed }) { return 0 }
            if key == nil { return 1 }
            return 2
        }
        // Earliest item date within a group, used as a stable tie-breaker.
        func earliestDate(_ key: UUID?) -> Date {
            (dict[key] ?? []).map(\.date).min() ?? .distantFuture
        }
        let sorted = dict.keys.sorted { keyA, keyB in
            let rankA = rank(keyA), rankB = rank(keyB)
            if rankA != rankB { return rankA < rankB }
            return earliestDate(keyA) < earliestDate(keyB)
        }
        return sorted.map { (tripId: $0, items: dict[$0] ?? []) }
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
            "check_in_date": makeISOFormatter().string(from: Date().addingTimeInterval(86_400)),
            "check_out_date": makeISOFormatter().string(from: Date().addingTimeInterval(4 * 86_400)),
            "end_date": makeISOFormatter().string(from: Date().addingTimeInterval(4 * 86_400))
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
            "end_date": makeISOFormatter().string(from: Date().addingTimeInterval(4 * 86_400))
        ]
    )
}
