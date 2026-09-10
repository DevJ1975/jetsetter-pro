// File: Features/Itinerary/ItineraryModel.swift

import Foundation

// MARK: - PackingItem

nonisolated struct PackingItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var isPacked: Bool

    init(id: UUID = UUID(), name: String, isPacked: Bool = false) {
        self.id = id
        self.name = name
        self.isPacked = isPacked
    }
}

// MARK: - Trip

nonisolated struct Trip: Identifiable, Codable {
    let id: UUID
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var items: [ItineraryItem]
    var packingList: [PackingItem]

    init(
        id: UUID = UUID(),
        name: String,
        destination: String,
        startDate: Date,
        endDate: Date,
        items: [ItineraryItem] = [],
        packingList: [PackingItem] = []
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.items = items
        self.packingList = packingList
    }

    // Custom decoder so existing saved trips (without packingList) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,              forKey: .id)
        name        = try c.decode(String.self,            forKey: .name)
        destination = try c.decode(String.self,            forKey: .destination)
        startDate   = try c.decode(Date.self,              forKey: .startDate)
        endDate     = try c.decode(Date.self,              forKey: .endDate)
        items       = try c.decode([ItineraryItem].self,   forKey: .items)
        packingList = (try? c.decode([PackingItem].self,   forKey: .packingList)) ?? []
    }

    var durationInDays: Int {
        let s = Calendar.current.startOfDay(for: startDate)
        let e = Calendar.current.startOfDay(for: endDate)
        return (Calendar.current.dateComponents([.day], from: s, to: e).day ?? 0) + 1
    }

    var sortedItems: [ItineraryItem] {
        items.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Share Text

    var shareText: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var lines: [String] = [
            name,
            "\(destination)  |  \(df.string(from: startDate)) – \(df.string(from: endDate))"
        ]

        if !sortedItems.isEmpty {
            lines += ["", "ITINERARY", String(repeating: "─", count: 28)]
            for item in sortedItems {
                let emoji: String
                switch item.type {
                case .flight:     emoji = "✈"
                case .hotel:      emoji = "🏨"
                case .activity:   emoji = "⭐"
                case .transport:  emoji = "🚗"
                case .restaurant: emoji = "🍽"
                }
                lines.append("\(emoji)  \(item.title)")
                var detail = "    \(df.string(from: item.startDate))"
                if let loc = item.location { detail += "  ·  \(loc)" }
                lines.append(detail)
            }
        }

        if !packingList.isEmpty {
            lines += ["", "PACKING LIST", String(repeating: "─", count: 28)]
            for item in packingList {
                lines.append("\(item.isPacked ? "☑" : "☐")  \(item.name)")
            }
        }

        lines += ["", "Shared from JetSetter Pro"]
        return lines.joined(separator: "\n")
    }
}

// MARK: - Booking Details

/// Optional cost captured on a manually-entered booking. Reference-only for now;
/// not linked into the Expense tracker.
nonisolated struct BookingCost: Codable, Equatable {
    var amount: Double
    var currencyCode: String   // ISO 4217, matches UserPreferences.supportedCurrencies
}

/// Structured detail for a manually-entered flight ticket (booked outside the app).
/// The ItineraryItem's `startDate`/`endDate` carry departure/arrival times.
nonisolated struct FlightBookingDetails: Codable, Equatable {
    var airline: String?
    var flightNumber: String?      // e.g. "AA 100"
    var originCode: String?        // IATA, e.g. "SFO"
    var destinationCode: String?   // IATA, e.g. "JFK"
    var seat: String?
    var cabinClass: String?        // Economy / Premium / Business / First
    var terminal: String?
    var gate: String?
}

/// Structured detail for a manually-entered hotel reservation.
/// Check-in/check-out use the ItineraryItem's `startDate`/`endDate`.
nonisolated struct HotelBookingDetails: Codable, Equatable {
    var address: String?
    var roomType: String?
    var phone: String?
}

/// Structured detail for a manually-entered rental car booking (stored as a
/// `.transport` item). Pickup/dropoff use the ItineraryItem's `startDate`/`endDate`.
nonisolated struct CarRentalDetails: Codable, Equatable {
    var vehicleClass: String?
    var vehicleDescription: String?  // "Toyota Corolla or similar"
    var pickupLocation: String?
    var dropoffLocation: String?
}

// MARK: - ItineraryItem

nonisolated struct ItineraryItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var type: ItineraryItemType
    var startDate: Date
    var endDate: Date?
    var location: String?
    var notes: String?
    var calendarEventIdentifier: String?

    // Structured booking detail for externally-booked travel. All optional so
    // pre-existing saved trips (and the cross-platform `items[]` wire contract)
    // decode cleanly — the synthesized decoder treats missing keys as nil.
    var confirmationNumber: String?
    var bookingProvider: String?     // airline / hotel chain / rental company
    var cost: BookingCost?
    var flightDetails: FlightBookingDetails?
    var hotelDetails: HotelBookingDetails?
    var carDetails: CarRentalDetails?

    var isSyncedToCalendar: Bool { calendarEventIdentifier != nil }

    /// True when the item carries any structured booking detail worth surfacing
    /// in the row/detail sheet beyond the base title/location.
    var hasBookingDetails: Bool {
        confirmationNumber != nil || cost != nil ||
        flightDetails != nil || hotelDetails != nil || carDetails != nil
    }

    /// A single compact fact for the itinerary row (seat/cabin, room type, or
    /// vehicle), or nil when there's nothing structured to show.
    var bookingKeyFact: String? {
        switch type {
        case .flight:
            let parts = [flightDetails?.seat.map { "Seat \($0)" }, flightDetails?.cabinClass]
                .compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .hotel:
            return hotelDetails?.roomType
        case .transport:
            return carDetails?.vehicleDescription ?? carDetails?.vehicleClass
        case .activity, .restaurant:
            return nil
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        type: ItineraryItemType,
        startDate: Date,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        calendarEventIdentifier: String? = nil,
        confirmationNumber: String? = nil,
        bookingProvider: String? = nil,
        cost: BookingCost? = nil,
        flightDetails: FlightBookingDetails? = nil,
        hotelDetails: HotelBookingDetails? = nil,
        carDetails: CarRentalDetails? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.calendarEventIdentifier = calendarEventIdentifier
        self.confirmationNumber = confirmationNumber
        self.bookingProvider = bookingProvider
        self.cost = cost
        self.flightDetails = flightDetails
        self.hotelDetails = hotelDetails
        self.carDetails = carDetails
    }
}

// MARK: - ItineraryItemType

// Raw values are UPPERCASE to match the cross-platform wire contract
// (the `type` field inside the `items[]` jsonb array). See IOS_PARITY_NOTES.md §2.
nonisolated enum ItineraryItemType: String, Codable, CaseIterable, Identifiable {
    case flight     = "FLIGHT"
    case hotel      = "HOTEL"
    case activity   = "ACTIVITY"
    case transport  = "TRANSPORT"
    case restaurant = "RESTAURANT"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flight:     return "Flight"
        case .hotel:      return "Hotel"
        case .activity:   return "Activity"
        case .transport:  return "Transport"
        case .restaurant: return "Restaurant"
        }
    }

    var systemImage: String {
        switch self {
        case .flight:     return "airplane"
        case .hotel:      return "bed.double.fill"
        case .activity:   return "star.fill"
        case .transport:  return "car.fill"
        case .restaurant: return "fork.knife"
        }
    }

    var color: String {
        switch self {
        case .flight:     return "#0066CC"
        case .hotel:      return "#0A7A5E"
        case .activity:   return "#C8860A"
        case .transport:  return "#1A2E40"
        case .restaurant: return "#CC3B1E"
        }
    }
}

// MARK: - Sample Data (Previews)

extension Trip {
    static let sample: Trip = {
        let now = Date()
        let calendar = Calendar.current

        return Trip(
            name: "Tokyo Spring Trip",
            destination: "Tokyo, Japan",
            startDate: calendar.date(byAdding: .day, value: 7, to: now) ?? now,
            endDate: calendar.date(byAdding: .day, value: 14, to: now) ?? now,
            items: [
                ItineraryItem(
                    title: "Flight to Tokyo (UA837)",
                    type: .flight,
                    startDate: calendar.date(byAdding: .day, value: 7, to: now) ?? now,
                    endDate: calendar.date(byAdding: .hour, value: 13, to: now) ?? now,
                    location: "SFO → NRT",
                    notes: "Gate B22 · Seat 14A"
                ),
                ItineraryItem(
                    title: "Check in — Park Hyatt Tokyo",
                    type: .hotel,
                    startDate: calendar.date(byAdding: .day, value: 8, to: now) ?? now,
                    endDate: calendar.date(byAdding: .day, value: 14, to: now) ?? now,
                    location: "3-7-1-2 Nishi Shinjuku, Tokyo"
                ),
                ItineraryItem(
                    title: "TeamLab Planets",
                    type: .activity,
                    startDate: calendar.date(byAdding: .day, value: 10, to: now) ?? now,
                    location: "6 Chome-1-16 Toyosu, Koto City, Tokyo"
                ),
                ItineraryItem(
                    title: "Dinner — Sukiyabashi Jiro",
                    type: .restaurant,
                    startDate: calendar.date(byAdding: .day, value: 11, to: now) ?? now,
                    location: "Chuo City, Tokyo"
                )
            ],
            packingList: [
                PackingItem(name: "Passport", isPacked: true),
                PackingItem(name: "Power adapter (Type A)"),
                PackingItem(name: "IC Card (Suica)"),
                PackingItem(name: "Yen cash")
            ]
        )
    }()
}
