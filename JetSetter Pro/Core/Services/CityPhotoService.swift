// File: Core/Services/CityPhotoService.swift
// Fetches a representative city photo via the Wikipedia / Wikimedia Commons API.
// Completely free — no API key required.

import Foundation

actor CityPhotoService {

    static let shared = CityPhotoService()

    private var cache: [String: URL?] = [:]

    // Maps common city names (lowercase) to their canonical Wikipedia article titles
    // for better photo results.
    private let overrides: [String: String] = [
        "new york": "New York City", "nyc": "New York City",
        "sf": "San Francisco", "san francisco": "San Francisco",
        "la": "Los Angeles", "los angeles": "Los Angeles",
        "chicago": "Chicago",
        "houston": "Houston, Texas",
        "phoenix": "Phoenix, Arizona",
        "philadelphia": "Philadelphia",
        "san antonio": "San Antonio, Texas",
        "san diego": "San Diego, California",
        "dallas": "Dallas",
        "austin": "Austin, Texas",
        "jacksonville": "Jacksonville, Florida",
        "fort worth": "Fort Worth, Texas",
        "columbus": "Columbus, Ohio",
        "charlotte": "Charlotte, North Carolina",
        "indianapolis": "Indianapolis",
        "seattle": "Seattle",
        "denver": "Denver",
        "washington": "Washington, D.C.", "dc": "Washington, D.C.",
        "nashville": "Nashville, Tennessee",
        "oklahoma city": "Oklahoma City",
        "el paso": "El Paso, Texas",
        "boston": "Boston",
        "portland": "Portland, Oregon",
        "las vegas": "Las Vegas",
        "memphis": "Memphis, Tennessee",
        "louisville": "Louisville, Kentucky",
        "baltimore": "Baltimore",
        "milwaukee": "Milwaukee",
        "albuquerque": "Albuquerque, New Mexico",
        "tucson": "Tucson, Arizona",
        "fresno": "Fresno, California",
        "sacramento": "Sacramento, California",
        "mesa": "Mesa, Arizona",
        "kansas city": "Kansas City, Missouri",
        "atlanta": "Atlanta",
        "omaha": "Omaha, Nebraska",
        "colorado springs": "Colorado Springs, Colorado",
        "raleigh": "Raleigh, North Carolina",
        "long beach": "Long Beach, California",
        "virginia beach": "Virginia Beach, Virginia",
        "miami": "Miami",
        "oakland": "Oakland, California",
        "minneapolis": "Minneapolis",
        "tulsa": "Tulsa, Oklahoma",
        "tampa": "Tampa, Florida",
        "arlington": "Arlington, Texas",
        "new orleans": "New Orleans",
        "honolulu": "Honolulu",
        "anchorage": "Anchorage, Alaska",
        "tokyo": "Tokyo", "london": "London", "paris": "Paris",
        "dubai": "Dubai", "singapore": "Singapore",
        "toronto": "Toronto", "sydney": "Sydney"
    ]

    /// Returns a thumbnail URL for the given city name, or nil if unavailable.
    func photoURL(for city: String) async -> URL? {
        let key = city.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let cached = cache[key] { return cached }

        let title = overrides[key] ?? city
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://en.wikipedia.org/w/api.php" +
                "?action=query&titles=\(encoded)&prop=pageimages" +
                "&format=json&pithumbsize=1200&origin=*")
        else {
            cache[key] = nil
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json      = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let query     = json["query"]   as? [String: Any],
                let pages     = query["pages"]  as? [String: Any],
                let page      = pages.values.first as? [String: Any],
                let thumbnail = page["thumbnail"] as? [String: Any],
                let source    = thumbnail["source"] as? String,
                let result    = URL(string: source)
            else {
                cache[key] = nil
                return nil
            }
            cache[key] = result
            return result
        } catch {
            cache[key] = nil
            return nil
        }
    }
}
