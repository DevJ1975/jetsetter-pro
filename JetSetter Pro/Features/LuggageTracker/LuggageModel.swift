// File: Features/LuggageTracker/LuggageModel.swift

import Foundation

// MARK: - Bag Status

enum BagStatus: String, Codable, CaseIterable {
    case checkedIn    = "checked_in"
    case inTransit    = "in_transit"
    case onBelt       = "on_belt"
    case loading      = "loading"
    case onAircraft   = "on_aircraft"
    case arrived      = "arrived"
    case atCarousel   = "at_carousel"
    case delayed      = "delayed"
    case missing      = "missing"
    case delivered    = "delivered"
    case unknown      = "unknown"

    var displayName: String {
        switch self {
        case .checkedIn:  return "Checked In"
        case .inTransit:  return "In Transit"
        case .onBelt:     return "On Belt"
        case .loading:    return "Loading Aircraft"
        case .onAircraft: return "Secured in Cargo"
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
        case .onBelt:     return "tray.full.fill"
        case .loading:    return "arrow.up.bin.fill"
        case .onAircraft: return "airplane.circle.fill"
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
        case .onBelt:     return "#3B9EF0"
        case .loading:    return "#7B3FBF"
        case .onAircraft: return "#1DB97D"
        case .arrived:    return "#0A7A5E"
        case .atCarousel: return "#0A7A5E"
        case .delayed:    return "#C8860A"
        case .missing:    return "#CC3B1E"
        case .delivered:  return "#0A7A5E"
        case .unknown:    return "#888888"
        }
    }
}

// MARK: - Bag Scan Event

/// A timestamped scan/handling event for a piece of luggage.
struct BagScanEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let location: String
    let scanType: ScanType
    let note: String?

    enum ScanType: String, Codable, CaseIterable {
        case checkIn
        case onBelt
        case loaderTransfer
        case securedInCargo
        case takeoff
        case landed
        case claimed

        var displayName: String {
            switch self {
            case .checkIn:        return "Check-In"
            case .onBelt:         return "On Belt"
            case .loaderTransfer: return "Loader Transfer"
            case .securedInCargo: return "Secured in Cargo"
            case .takeoff:        return "Takeoff"
            case .landed:         return "Landed"
            case .claimed:        return "Claimed"
            }
        }

        var systemImage: String {
            switch self {
            case .checkIn:        return "checkmark.circle.fill"
            case .onBelt:         return "tray.full.fill"
            case .loaderTransfer: return "arrow.up.bin.fill"
            case .securedInCargo: return "airplane.circle.fill"
            case .takeoff:        return "airplane.departure"
            case .landed:         return "airplane.arrival"
            case .claimed:        return "checkmark.seal.fill"
            }
        }

        var colorHex: String {
            switch self {
            case .checkIn:        return "#0066CC"
            case .onBelt:         return "#3B9EF0"
            case .loaderTransfer: return "#7B3FBF"
            case .securedInCargo: return "#1DB97D"
            case .takeoff:        return "#0A7A5E"
            case .landed:         return "#0A7A5E"
            case .claimed:        return "#0A7A5E"
            }
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date,
        location: String,
        scanType: ScanType,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.location = location
        self.scanType = scanType
        self.note = note
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
    var scanHistory: [BagScanEvent]

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
        lastChecked: Date? = nil,
        scanHistory: [BagScanEvent] = []
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
        self.scanHistory = scanHistory
    }

    var isTrackable: Bool { bagTagNumber != nil || hasAirTag }
}

// MARK: - Codable Backward Compatibility

extension Bag {
    private enum CodingKeys: String, CodingKey {
        case id, nickname, description, airline, flightNumber, bagTagNumber
        case hasAirTag, status, lastLocation, lastChecked, scanHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id            = try c.decode(UUID.self, forKey: .id)
        self.nickname      = try c.decode(String.self, forKey: .nickname)
        self.description   = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.airline       = try c.decodeIfPresent(String.self, forKey: .airline)
        self.flightNumber  = try c.decodeIfPresent(String.self, forKey: .flightNumber)
        self.bagTagNumber  = try c.decodeIfPresent(String.self, forKey: .bagTagNumber)
        self.hasAirTag     = try c.decodeIfPresent(Bool.self, forKey: .hasAirTag) ?? false
        self.status        = try c.decodeIfPresent(BagStatus.self, forKey: .status) ?? .unknown
        self.lastLocation  = try c.decodeIfPresent(String.self, forKey: .lastLocation)
        self.lastChecked   = try c.decodeIfPresent(Date.self, forKey: .lastChecked)
        self.scanHistory   = try c.decodeIfPresent([BagScanEvent].self, forKey: .scanHistory) ?? []
    }
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
        case "on_belt":                         return .onBelt
        case "loading":                         return .loading
        case "on_aircraft", "secured":          return .onAircraft
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
