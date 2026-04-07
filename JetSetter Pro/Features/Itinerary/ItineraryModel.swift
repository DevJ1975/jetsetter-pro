// File: Features/Itinerary/ItineraryModel.swift

import Foundation

// MARK: - Trip

/// A single trip containing a list of itinerary items (flights, hotels, activities, etc.)
struct Trip: Identifiable, Codable {
    let id: UUID
    var name: String           // e.g. "Tokyo April 2025"
    var destination: String    // e.g. "Tokyo, Japan"
    var startDate: Date
    var endDate: Date
    var items: [ItineraryItem]

    init(
        id: UUID = UUID(),
        name: String,
        destination: String,
        startDate: Date,
        endDate: Date,
        items: [ItineraryItem] = []
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.items = items
    }

    /// Duration of the trip in days
    var durationInDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    /// Items sorted chronologically by start date
    var sortedItems: [ItineraryItem] {
        items.sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - ItineraryItem

/// A single event within a trip (flight, hotel, activity, etc.)
struct ItineraryItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var type: ItineraryItemType
    var startDate: Date
    var endDate: Date?
    var location: String?
    var notes: String?
    /// Stores the EventKit event identifier after syncing to Calendar; nil if not synced
    var calendarEventIdentifier: String?

    var isSyncedToCalendar: Bool { calendarEventIdentifier != nil }

    init(
        id: UUID = UUID(),
        title: String,
        type: ItineraryItemType,
        startDate: Date,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        calendarEventIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.calendarEventIdentifier = calendarEventIdentifier
    }
}

// MARK: - ItineraryItemType

enum ItineraryItemType: String, Codable, CaseIterable, Identifiable {
    case flight
    case hotel
    case activity
    case transport
    case restaurant

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flight:    return "Flight"
        case .hotel:     return "Hotel"
        case .activity:  return "Activity"
        case .transport: return "Transport"
        case .restaurant: return "Restaurant"
        }
    }

    var systemImage: String {
        switch self {
        case .flight:    return "airplane"
        case .hotel:     return "bed.double.fill"
        case .activity:  return "star.fill"
        case .transport: return "car.fill"
        case .restaurant: return "fork.knife"
        }
    }

    var color: String {
        switch self {
        case .flight:    return "#0066CC"   // accent blue
        case .hotel:     return "#0A7A5E"   // success green
        case .activity:  return "#C8860A"   // amber
        case .transport: return "#1A2E40"   // primary navy
        case .restaurant: return "#CC3B1E"  // coral red
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
            ]
        )
    }()
}
