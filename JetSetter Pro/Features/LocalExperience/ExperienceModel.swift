// File: Features/LocalExperience/ExperienceModel.swift
// Models for the Local Experience Engine feature (Feature 5).

import Foundation
import CoreLocation

// MARK: - ExperienceCategory

enum ExperienceCategory: String, Codable, CaseIterable, Identifiable {
    case restaurant  = "Restaurant"
    case attraction  = "Attraction"
    case hiddenGem   = "Hidden Gem"
    case event       = "Event"
    case bar         = "Bar"
    case cafe        = "Cafe"
    case shopping    = "Shopping"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .attraction: return "camera.fill"
        case .hiddenGem:  return "sparkles"
        case .event:      return "ticket.fill"
        case .bar:        return "wineglass.fill"
        case .cafe:       return "cup.and.saucer.fill"
        case .shopping:   return "bag.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .restaurant: return "#E84040"
        case .attraction: return "#3B9EF0"
        case .hiddenGem:  return "#E8A020"
        case .event:      return "#7B3FBF"
        case .bar:        return "#C8860A"
        case .cafe:       return "#1DB97D"
        case .shopping:   return "#0A7A5E"
        }
    }
}

// MARK: - ExperienceTimeSlot

enum ExperienceTimeSlot: String, CaseIterable, Codable {
    case rightNow  = "Right Now"
    case tonight   = "Tonight"
    case thisTrip  = "This Trip"
}

// MARK: - PriceLevel

enum PriceLevel: Int, Codable {
    case free       = 0
    case budget     = 1
    case moderate   = 2
    case upscale    = 3
    case luxury     = 4

    var symbol: String { self == .free ? "Free" : String(repeating: "$", count: rawValue) }
}

// MARK: - Experience

/// A single recommended experience. Today every item comes from Apple Maps
/// (MapKit local search); the other sources remain for future feeds.
struct Experience: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: ExperienceCategory
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double          // 0–5.0
    let reviewCount: Int
    let priceLevel: PriceLevel
    let distanceMeters: Double? // from user's current location
    let openNow: Bool?
    let photoUrl: String?       // Image URL when a source provides one (Apple Maps does not)
    let bookingUrl: String?     // The venue's own site when known, else an Apple Maps link
    let eventDate: Date?        // Only set for .event category
    let aiReason: String?       // On-device (Apple Intelligence) one-line reason this suits the traveler
    let source: ExperienceSource
    /// Which section a place belongs in when it has no event date (cafés → Right
    /// Now, bars → Tonight, sights → This Trip).
    var slotOverride: ExperienceTimeSlot? = nil

    /// True when the source supplies ratings; Apple Maps listings don't, so the
    /// UI hides the star row instead of showing a fake 0.0.
    var hasRating: Bool { rating > 0 }

    /// Copy with a different reason attached (fields are immutable by design).
    func withReason(_ reason: String?) -> Experience {
        Experience(id: id, name: name, category: category, address: address, latitude: latitude, longitude: longitude,
                   rating: rating, reviewCount: reviewCount, priceLevel: priceLevel, distanceMeters: distanceMeters,
                   openNow: openNow, photoUrl: photoUrl, bookingUrl: bookingUrl, eventDate: eventDate,
                   aiReason: reason, source: source, slotOverride: slotOverride)
    }

    var distanceFormatted: String {
        guard let d = distanceMeters else { return "" }
        return d < 1000
            ? "\(Int(d))m away"
            : String(format: "%.1f km away", d / 1000)
    }

    /// Whether the venue is currently open. Nil (unknown) is treated as not-closed
    /// so we never hide a place we simply have no hours for.
    var isClosedNow: Bool { openNow == false }

    /// Call-to-action label for the booking button, driven by source + category
    /// so we don't mislabel ticketed attractions/events as restaurant "reservations".
    var bookActionLabel: String {
        switch source {
        case .openTable, .resy:
            return "Reserve"
        case .eventbrite:
            return "Get Tickets"
        case .appleMaps:
            return "Open in Maps"
        case .googlePlaces, .aiCurated:
            switch category {
            case .restaurant, .bar, .cafe:
                return "Reserve"
            case .attraction:
                return "Book Tickets"
            case .event:
                return "Get Tickets"
            case .hiddenGem, .shopping:
                return "View"
            }
        }
    }

    var timeSlot: ExperienceTimeSlot {
        guard let eventDate = eventDate else { return slotOverride ?? .rightNow }
        let hours = Calendar.current.dateComponents([.hour], from: Date(), to: eventDate).hour ?? 0
        if hours < 0   { return .thisTrip }   // already-passed events are not happening "Right Now"
        if hours < 3   { return .rightNow }
        if hours < 12  { return .tonight }
        return .thisTrip
    }
}

enum ExperienceSource: String, Codable {
    case appleMaps    = "apple_maps"
    case googlePlaces = "google_places"
    case eventbrite   = "eventbrite"
    case openTable    = "open_table"
    case resy         = "resy"
    case aiCurated    = "ai_curated"
}

// MARK: - RecommendationContext

/// Context the on-device ranker considers when ordering recommendations.
struct RecommendationContext: Codable {
    let tripType: String           // "business", "leisure", "mixed"
    let timeOfDay: String          // "morning", "afternoon", "evening", "night"
    let weatherCondition: String   // "sunny", "cloudy", "rainy", "cold"
    let destinationCity: String
    let userPastCategories: [String] // categories from the on-device learned profile
}
