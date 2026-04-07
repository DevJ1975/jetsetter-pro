// File: Features/LuggageTracker/LuggageModel.swift

import Foundation

// MARK: - Bag Status

enum BagStatus: String, Codable, CaseIterable {
    case checkedIn   = "checked_in"
    case inTransit   = "in_transit"
    case arrived     = "arrived"
    case atCarousel  = "at_carousel"
    case delayed     = "delayed"
    case missing     = "missing"
    case delivered   = "delivered"
    case unknown     = "unknown"

    var displayName: String {
        switch self {
        case .checkedIn:  return "Checked In"
        case .inTransit:  return "In Transit"
        case .arrived:    return "Arrived"
        case .atCarousel: return "At Baggage Claim"
        case .delayed:    return "Delayed"
        case .missing:    return "Cannot Locate"
        case .delivered:  return "Delivered"
        case .unknown:    return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .checkedIn:  return "checkmark.circle.fill"
        case .inTransit:  return "airplane"
        case .arrived:    return "airplane.arrival"
        case .atCarousel: return "arrow.circlepath"
        case .delayed:    return "clock.badge.exclamationmark.fill"
        case .missing:    return "exclamationmark.triangle.fill"
        case .delivered:  return "checkmark.seal.fill"
        case .unknown:    return "questionmark.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .checkedIn:  return "#0066CC"
        case .inTransit:  return "#0066CC"
        case .arrived:    return "#0A7A5E"
        case .atCarousel: return "#0A7A5E"
        case .delayed:    return "#C8860A"
        case .missing:    return "#CC3B1E"
        case .delivered:  return "#0A7A5E"
        case .unknown:    return "#888888"
        }
    }
}

// MARK: - Bag

/// A single piece of luggage registered in the tracker.
struct Bag: Identifiable, Codable {
    let id: UUID
    var nickname: String          // User-given name e.g. "Blue Samsonite"
    var description: String       // e.g. "Large suitcase, blue, hard shell"
    var airline: String?
    var flightNumber: String?
    var bagTagNumber: String?     // 10-digit IATA bag tag for WorldTracer lookup
    var hasAirTag: Bool           // User has an AirTag attached to this bag
    var status: BagStatus
    var lastLocation: String?     // Last reported location e.g. "Chicago O'Hare"
    var lastChecked: Date?

    init(
        id: UUID = UUID(),
        nickname: String,
        description: String = "",
        airline: String? = nil,
        flightNumber: String? = nil,
        bagTagNumber: String? = nil,
        hasAirTag: Bool = false,
        status: BagStatus = .unknown,
        lastLocation: String? = nil,
        lastChecked: Date? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.description = description
        self.airline = airline
        self.flightNumber = flightNumber
        self.bagTagNumber = bagTagNumber
        self.hasAirTag = hasAirTag
        self.status = status
        self.lastLocation = lastLocation
        self.lastChecked = lastChecked
    }

    var isTrackable: Bool { bagTagNumber != nil || hasAirTag }
}

// MARK: - WorldTracer API Response

/// Bag trace result returned by the SITA WorldTracer REST API.
struct WorldTracerBagResponse: Codable {
    let tagNumber: String
    let status: String
    let lastLocation: String?
    let flightNumber: String?
    let airline: String?
    let expectedDelivery: String?
    let remarks: String?

    /// Maps the WorldTracer status string to our typed BagStatus enum
    var mappedStatus: BagStatus {
        switch status.lowercased() {
        case "checked", "checked_in":           return .checkedIn
        case "in_transit", "on_flight":         return .inTransit
        case "arrived", "delivered_airport":    return .arrived
        case "at_carousel", "ready_for_pickup": return .atCarousel
        case "delayed":                         return .delayed
        case "missing", "lost", "not_found":    return .missing
        case "delivered", "delivered_home":     return .delivered
        default:                                return .unknown
        }
    }
}

// MARK: - Sample Data (Previews)

extension Bag {
    static let sampleBags: [Bag] = [
        Bag(
            nickname: "Blue Samsonite",
            description: "Large blue hard-shell suitcase",
            airline: "United Airlines",
            flightNumber: "UA837",
            bagTagNumber: "0163845678",
            hasAirTag: true,
            status: .inTransit,
            lastLocation: "Chicago O'Hare (ORD)",
            lastChecked: Date()
        ),
        Bag(
            nickname: "Black Carry-On",
            description: "Small black soft-shell carry-on",
            hasAirTag: true,
            status: .delivered,
            lastChecked: Date()
        ),
        Bag(
            nickname: "Golf Bag",
            description: "Callaway golf bag in travel case",
            airline: "Delta Air Lines",
            flightNumber: "DL445",
            bagTagNumber: "0063921045",
            hasAirTag: false,
            status: .delayed,
            lastLocation: "Atlanta (ATL)",
            lastChecked: Calendar.current.date(byAdding: .minute, value: -30, to: Date())
        )
    ]
}
