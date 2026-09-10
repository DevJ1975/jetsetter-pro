// File: Features/RentalCar/RentalCarModel.swift
//
// Rental cars are found with MapKit (Apple's own points-of-interest data), so
// there is no partner API and no key. The app finds rental counters near the
// pickup point, groups them by brand, and hands the user to the brand's site
// in-app to see rates and book. Rates are never invented.

import Foundation
import CoreLocation
import MapKit

// MARK: - Rental Brand

/// Brands recognised from a counter's name. Anything else is `.other`.
enum RentalBrand: String, CaseIterable, Codable {
    case enterprise, hertz, national, avis, budget, sixt, alamo, thrifty, dollar, other

    var displayName: String {
        switch self {
        case .enterprise: return "Enterprise"
        case .hertz:      return "Hertz"
        case .national:   return "National"
        case .avis:       return "Avis"
        case .budget:     return "Budget"
        case .sixt:       return "Sixt"
        case .alamo:      return "Alamo"
        case .thrifty:    return "Thrifty"
        case .dollar:     return "Dollar"
        case .other:      return "Other"
        }
    }

    /// Brand accent colour (hex).
    var colorHex: String {
        switch self {
        case .enterprise: return "#1B7A3E"
        case .hertz:      return "#C9A100"
        case .national:   return "#1F6F3A"
        case .avis:       return "#D4002A"
        case .budget:     return "#1D5FB8"
        case .sixt:       return "#FF5F00"
        case .alamo:      return "#0D6EB8"
        case .thrifty:    return "#1E4E9C"
        case .dollar:     return "#C8102E"
        case .other:      return "#8B92A8"
        }
    }

    /// Brand booking site, presented in-app via `InAppWebView`.
    var websiteURL: URL? {
        switch self {
        case .enterprise: return URL(string: "https://www.enterprise.com")
        case .hertz:      return URL(string: "https://www.hertz.com")
        case .national:   return URL(string: "https://www.nationalcar.com")
        case .avis:       return URL(string: "https://www.avis.com")
        case .budget:     return URL(string: "https://www.budget.com")
        case .sixt:       return URL(string: "https://www.sixt.com")
        case .alamo:      return URL(string: "https://www.alamo.com")
        case .thrifty:    return URL(string: "https://www.thrifty.com")
        case .dollar:     return URL(string: "https://www.dollar.com")
        case .other:      return nil
        }
    }

    /// Detects the brand from a map item name ("Hertz Car Rental", "Enterprise Rent-A-Car").
    static func detect(from name: String) -> RentalBrand {
        let lower = name.lowercased()
        for brand in allCases where brand != .other {
            if lower.contains(brand.rawValue) { return brand }
        }
        return .other
    }

    /// Brands shown as filter chips, in display order.
    static let filterable: [RentalBrand] = [.enterprise, .hertz, .national, .avis, .budget, .sixt, .alamo]
}

// MARK: - Rental Counter

/// A rental-car counter or lot found near the pickup point.
struct RentalCounter: Identifiable {
    let id: String
    let brand: RentalBrand
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let phoneNumber: String?
    /// The counter's own page when MapKit has one; otherwise the brand site.
    let websiteURL: URL?
    /// Kept so "Directions" can open Apple Maps with the real place.
    let mapItem: MKMapItem

    var formattedDistance: String {
        Measurement(value: distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var bookingURL: URL? { websiteURL ?? brand.websiteURL }

    var phoneURL: URL? {
        guard let phoneNumber else { return nil }
        let digits = phoneNumber.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel://\(digits)")
    }
}

// MARK: - Search Parameters

struct RentalCarSearchParams {
    var pickupLocation: String = ""
    var pickupDate: Date = .now
    var dropoffDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now

    var numberOfDays: Int {
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: pickupDate), to: cal.startOfDay(for: dropoffDate))
        return max(diff.day ?? 1, 1)
    }
}

// MARK: - Sample Data (Previews)

extension RentalCounter {
    static func sample(brand: RentalBrand, name: String, distance: Double) -> RentalCounter {
        let coordinate = CLLocationCoordinate2D(latitude: 41.9742, longitude: -87.9073)
        let placemark = MKPlacemark(coordinate: coordinate)
        return RentalCounter(
            id: "\(brand.rawValue)-\(Int(distance))",
            brand: brand,
            name: name,
            address: "10000 Bessie Coleman Dr, Chicago, IL 60666",
            coordinate: coordinate,
            distanceMeters: distance,
            phoneNumber: "+1 (800) 555-0100",
            websiteURL: brand.websiteURL,
            mapItem: MKMapItem(placemark: placemark)
        )
    }

    static let samples: [RentalCounter] = [
        .sample(brand: .enterprise, name: "Enterprise Rent-A-Car", distance: 1_200),
        .sample(brand: .hertz,      name: "Hertz Car Rental",      distance: 1_450),
        .sample(brand: .avis,       name: "Avis Car Rental",       distance: 2_300)
    ]
}
