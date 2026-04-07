// File: Features/GroundTransport/GroundTransportModel.swift

import Foundation
import CoreLocation

// MARK: - Ride Provider

enum RideProvider: String, CaseIterable {
    case uber
    case lyft

    var displayName: String {
        switch self {
        case .uber: return "Uber"
        case .lyft: return "Lyft"
        }
    }

    var iconName: String {
        switch self {
        case .uber: return "car.fill"
        case .lyft: return "car.2.fill"
        }
    }
}

// MARK: - Ride Option (unified UI model)

/// A normalized ride option shown in the UI, combining data from Uber or Lyft.
struct RideOption: Identifiable {
    let id: String
    let provider: RideProvider
    let productName: String       // "UberX", "Comfort", "Lyft", "Lyft XL"
    let priceRange: String        // "$12–$18"
    let estimatedMinutes: Int     // minutes to pickup
    let isSurging: Bool

    /// Opens the Uber or Lyft app for the given route, or falls back to the App Store.
    func deepLinkURL(pickup: CLLocation?, dropoffAddress: String) -> URL? {
        let encoded = dropoffAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        switch provider {
        case .uber:
            // Uber deep link with optional pickup coordinates
            var uberLink = "uber://?action=setPickup"
            if let pickup = pickup {
                uberLink += "&pickup[latitude]=\(pickup.coordinate.latitude)"
                uberLink += "&pickup[longitude]=\(pickup.coordinate.longitude)"
            } else {
                uberLink += "&pickup=my_location"
            }
            uberLink += "&dropoff[formatted_address]=\(encoded)"
            uberLink += "&product_id=\(id)"
            return URL(string: uberLink)

        case .lyft:
            // Lyft deep link
            var lyftLink = "lyft://ridetype?id=\(id)"
            if let pickup = pickup {
                lyftLink += "&pickup[latitude]=\(pickup.coordinate.latitude)"
                lyftLink += "&pickup[longitude]=\(pickup.coordinate.longitude)"
            }
            lyftLink += "&destination[address]=\(encoded)"
            return URL(string: lyftLink)
        }
    }

    /// App Store fallback if the ride app is not installed
    var appStoreURL: URL? {
        switch provider {
        case .uber: return URL(string: "https://apps.apple.com/app/uber/id368677368")
        case .lyft: return URL(string: "https://apps.apple.com/app/lyft/id529379082")
        }
    }
}

// MARK: - Uber API Response Models

struct UberPriceEstimatesResponse: Codable {
    let prices: [UberPriceEstimate]
}

struct UberPriceEstimate: Codable {
    let productId: String
    let displayName: String
    let estimate: String          // e.g. "$12–$15" or "Metered"
    let minimumCost: Int?         // in cents
    let duration: Int?            // seconds
    let surgeMultiplier: Double?

    var isSurging: Bool { (surgeMultiplier ?? 1.0) > 1.0 }

    var estimatedPickupMinutes: Int { max(1, (duration ?? 300) / 60) }
}

// MARK: - Lyft API Response Models

struct LyftCostEstimatesResponse: Codable {
    let costEstimates: [LyftCostEstimate]
}

struct LyftCostEstimate: Codable {
    let rideType: String           // "lyft", "lyft_xl", "lyft_black"
    let displayName: String
    let estimatedCostCentsMin: Int
    let estimatedCostCentsMax: Int
    let estimatedDurationSeconds: Int
    let isValidEstimate: Bool?
    let primetime_percentage: String? // e.g. "25%"

    var isSurging: Bool { primetime_percentage != nil && primetime_percentage != "0%" }

    /// Formatted price range string e.g. "$12–$18"
    var priceRange: String {
        let min = estimatedCostCentsMin / 100
        let max = estimatedCostCentsMax / 100
        return "$\(min)–$\(max)"
    }

    var estimatedPickupMinutes: Int { max(1, estimatedDurationSeconds / 60) }
}

// MARK: - Lyft Token Response

struct LyftTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
}

// MARK: - Sample Data (Previews)

extension RideOption {
    static let sampleOptions: [RideOption] = [
        RideOption(
            id: "a1111c8c-c720-46c3-8534-2fcdd730040d",
            provider: .uber,
            productName: "UberX",
            priceRange: "$14–$18",
            estimatedMinutes: 4,
            isSurging: false
        ),
        RideOption(
            id: "821415d8-3bd5-4e27-9604-194e4359a449",
            provider: .uber,
            productName: "Comfort",
            priceRange: "$18–$24",
            estimatedMinutes: 6,
            isSurging: false
        ),
        RideOption(
            id: "lyft",
            provider: .lyft,
            productName: "Lyft",
            priceRange: "$12–$16",
            estimatedMinutes: 3,
            isSurging: false
        ),
        RideOption(
            id: "lyft_xl",
            provider: .lyft,
            productName: "Lyft XL",
            priceRange: "$22–$30",
            estimatedMinutes: 7,
            isSurging: true
        )
    ]
}
