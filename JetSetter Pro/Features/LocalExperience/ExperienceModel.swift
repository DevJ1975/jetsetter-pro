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

enum ExperienceTimeSlot: String, CaseIterable {
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

    var symbol: String { String(repeating: "$", count: max(rawValue, 1)) }
}

// MARK: - Experience

/// A single recommended experience, sourced from Google Places, Eventbrite, or AI curation.
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
    let photoUrl: String?       // Google Places photo reference or Eventbrite image URL
    let bookingUrl: String?     // OpenTable, Resy, or Eventbrite deep link
    let eventDate: Date?        // Only set for .event category
    let aiReason: String?       // Claude-generated 1-line personalization reason
    let source: ExperienceSource

    var distanceFormatted: String {
        guard let d = distanceMeters else { return "" }
        return d < 1000
            ? "\(Int(d))m away"
            : String(format: "%.1f km away", d / 1000)
    }

    var timeSlot: ExperienceTimeSlot {
        guard let eventDate = eventDate else { return .rightNow }
        let hours = Calendar.current.dateComponents([.hour], from: Date(), to: eventDate).hour ?? 0
        if hours < 3   { return .rightNow }
        if hours < 12  { return .tonight }
        return .thisTrip
    }
}

enum ExperienceSource: String, Codable {
    case googlePlaces = "google_places"
    case eventbrite   = "eventbrite"
    case openTable    = "open_table"
    case resy         = "resy"
    case aiCurated    = "ai_curated"
}

// MARK: - RecommendationContext

/// The full context passed to Claude API for personalizing recommendations.
struct RecommendationContext: Codable {
    let tripType: String           // "business", "leisure", "mixed"
    let timeOfDay: String          // "morning", "afternoon", "evening", "night"
    let weatherCondition: String   // "sunny", "cloudy", "rainy", "cold"
    let destinationCity: String
    let userPastCategories: [String] // categories from past Supabase activity logs
}
