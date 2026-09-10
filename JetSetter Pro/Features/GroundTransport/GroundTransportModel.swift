// File: Features/GroundTransport/GroundTransportModel.swift
//
// Ground transport hands the user to Uber or Lyft with the route already
// filled in. Neither company offers a public fare-estimate API any more
// (Lyft retired it; Uber's needs a partner OAuth app), so the app shows an
// honest driving time and distance from MapKit and lets the ride app quote
// the fare.

import Foundation
import CoreLocation

// MARK: - Ride Provider

enum RideProvider: String, CaseIterable, Identifiable {
    case uber
    case lyft

    var id: String { rawValue }

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

    var colorHex: String {
        switch self {
        case .uber: return "#000000"
        case .lyft: return "#FF00BF"
        }
    }

    /// Opens the provider's ride flow with pickup and destination pre-filled.
    /// These are the documented universal-link formats; on a phone with the app
    /// installed they open the app, otherwise the mobile site.
    func rideURL(pickup: CLLocation?, dropoff: CLLocation, dropoffAddress: String) -> URL? {
        var components: URLComponents
        var items: [URLQueryItem] = []
        switch self {
        case .uber:
            components = URLComponents(string: "https://m.uber.com/ul/") ?? URLComponents()
            items.append(URLQueryItem(name: "action", value: "setPickup"))
            if let pickup {
                items.append(URLQueryItem(name: "pickup[latitude]",  value: String(pickup.coordinate.latitude)))
                items.append(URLQueryItem(name: "pickup[longitude]", value: String(pickup.coordinate.longitude)))
            } else {
                items.append(URLQueryItem(name: "pickup", value: "my_location"))
            }
            items.append(URLQueryItem(name: "dropoff[latitude]",  value: String(dropoff.coordinate.latitude)))
            items.append(URLQueryItem(name: "dropoff[longitude]", value: String(dropoff.coordinate.longitude)))
            items.append(URLQueryItem(name: "dropoff[nickname]",  value: dropoffAddress))
            items.append(URLQueryItem(name: "dropoff[formatted_address]", value: dropoffAddress))
        case .lyft:
            components = URLComponents(string: "https://lyft.com/ride") ?? URLComponents()
            items.append(URLQueryItem(name: "id", value: "lyft"))
            if let pickup {
                items.append(URLQueryItem(name: "pickup[latitude]",  value: String(pickup.coordinate.latitude)))
                items.append(URLQueryItem(name: "pickup[longitude]", value: String(pickup.coordinate.longitude)))
            }
            items.append(URLQueryItem(name: "destination[latitude]",  value: String(dropoff.coordinate.latitude)))
            items.append(URLQueryItem(name: "destination[longitude]", value: String(dropoff.coordinate.longitude)))
        }
        components.queryItems = items
        return components.url
    }
}

// MARK: - Ride Option (unified UI model)

/// One provider's card for the current route.
struct RideOption: Identifiable {
    let provider: RideProvider
    /// Driving time for the route from MapKit, in minutes.
    let estimatedMinutes: Int
    /// Route distance in meters.
    let distanceMeters: Double
    /// Pre-filled ride link for the provider.
    let rideURL: URL?

    var id: String { provider.rawValue }

    var formattedDistance: String {
        Measurement(value: distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

// MARK: - Sample Data (Previews)

extension RideOption {
    static let sampleOptions: [RideOption] = [
        RideOption(provider: .uber, estimatedMinutes: 18, distanceMeters: 11_600, rideURL: URL(string: "https://m.uber.com/ul/")),
        RideOption(provider: .lyft, estimatedMinutes: 18, distanceMeters: 11_600, rideURL: URL(string: "https://lyft.com/ride"))
    ]
}
