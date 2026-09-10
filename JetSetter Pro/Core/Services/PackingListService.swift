// File: Core/Services/PackingListService.swift
// Generates AI-powered packing lists for Feature 2 using:
//   - WeatherKit daily forecast (Open-Meteo fallback) for destination weather
//   - Keyword-based activity extraction from itinerary items
//   - Airline baggage rule lookup (20 airlines)
//   - On-device Apple Intelligence (PackingListGenerator) for item generation,
//     with a static fallback list when the model is unavailable. No network AI.

import Foundation
import NaturalLanguage

// MARK: - Destination Forecast

struct DestinationForecast {
    let avgHighF: Double
    let avgLowF: Double
    let rainyDays: Int
    let snowyDays: Int
    let dominantCondition: String

    /// Human-readable summary passed to the model as context.
    var summary: String {
        var parts = [
            "avg highs \(Int(avgHighF))°F / \(Int((avgHighF - 32.0) * 5.0 / 9.0))°C",
            "avg lows \(Int(avgLowF))°F / \(Int((avgLowF - 32.0) * 5.0 / 9.0))°C"
        ]
        if rainyDays > 0 { parts.append("\(rainyDays) rainy day(s)") }
        if snowyDays > 0 { parts.append("\(snowyDays) snowy day(s)") }
        parts.append(dominantCondition)
        return parts.joined(separator: ", ")
    }

    var isCold: Bool { avgHighF < 50 }
    var isHot:  Bool { avgHighF > 82 }
    var isWet:  Bool { rainyDays >= 2 }
    var isSnowy: Bool { snowyDays >= 1 }
}

// MARK: - PackingListService

actor PackingListService {

    static let shared = PackingListService()
    private init() {}

    // MARK: - Activity Keywords

    /// Maps lowercase keyword fragments to human-readable activity labels.
    private let activityKeywords: [(keyword: String, label: String)] = [
        ("beach",      "beach/coastal activities"),
        ("pool",       "swimming"),
        ("swim",       "swimming"),
        ("snorkel",    "snorkeling"),
        ("surf",       "surfing"),
        ("dive",       "scuba diving"),
        ("ski",        "skiing/snowboarding"),
        ("snowboard",  "snowboarding"),
        ("hike",       "hiking"),
        ("trek",       "trekking"),
        ("trail",      "hiking"),
        ("camping",    "camping/outdoor"),
        ("safari",     "safari"),
        ("golf",       "golf"),
        ("tennis",     "tennis"),
        ("gym",        "gym workouts"),
        ("yoga",       "yoga"),
        ("spa",        "spa/wellness"),
        ("conference", "business/conference"),
        ("meeting",    "business meetings"),
        ("wedding",    "formal event"),
        ("gala",       "formal event"),
        ("museum",     "cultural sightseeing"),
        ("temple",     "cultural sightseeing"),
        ("church",     "cultural sightseeing"),
        ("concert",    "live events"),
        ("festival",   "festivals"),
        ("cooking",    "culinary activities"),
        ("wine",       "wine/food tours"),
        ("cycling",    "cycling")
    ]

    // MARK: - Public Generation Pipeline

    /// Full pipeline: geocode → forecast → activity extraction → on-device
    /// generation. Streams cumulative `[SmartPackingItem]` snapshots so the UI
    /// can fill in rows as the model writes them; the last snapshot is the
    /// complete list. When Apple Intelligence is unavailable (or fails before
    /// producing anything) the static fallback list is yielded once instead.
    func packingItemsStream(for trip: Trip) -> AsyncThrowingStream<[SmartPackingItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Step 1: Geocode and fetch forecast
                    let coords = try await self.geocode(trip.destination)
                    let forecastDays = max(1, min(trip.durationInDays, 7))
                    let forecast = try await self.fetchForecast(lat: coords.lat, lon: coords.lon, days: forecastDays)

                    // Step 2: Extract activities (keyword table + on-device content
                    // tagging when Apple Intelligence is available) and detect airline
                    var activities = self.extractActivities(from: trip)
                    let tagged = await ActivityTagger.shared.activities(in: trip.items.map(\.title))
                    for tag in tagged where !activities.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                        activities.append(tag)
                    }
                    let airlineIATA = self.detectAirlineIATA(from: trip)
                    let baggageRule = airlineIATA.flatMap { AirlineBaggageRule.rules[$0] }

                    // Step 3: Build the prompt and generate on device
                    let prompt = self.buildPrompt(
                        trip: trip,
                        forecast: forecast,
                        activities: activities,
                        baggageRule: baggageRule,
                        detectedAirlineIATA: airlineIATA
                    )

                    let generator = await PackingListGenerator.shared
                    guard await generator.isAvailable else {
                        continuation.yield(self.fallbackItems(for: forecast))
                        continuation.finish()
                        return
                    }

                    var last: [SmartPackingItem] = []
                    do {
                        for try await snapshot in await generator.stream(prompt: prompt) {
                            last = snapshot
                            continuation.yield(snapshot)
                        }
                    } catch {
                        // Guardrail / context / cancellation mid-generation: keep
                        // whatever was produced, or fall back if nothing was.
                        guard !Task.isCancelled else { continuation.finish(); return }
                        if last.isEmpty { continuation.yield(self.fallbackItems(for: forecast)) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The complete list — the last snapshot of `packingItemsStream(for:)`.
    func generatePackingItems(for trip: Trip) async throws -> [SmartPackingItem] {
        var last: [SmartPackingItem] = []
        for try await snapshot in packingItemsStream(for: trip) { last = snapshot }
        return last
    }

    // MARK: - Geocoding

    private func geocode(_ destination: String) async throws -> (lat: Double, lon: Double) {
        // Destinations often arrive as "City, Country" (e.g. "Tokyo, Japan").
        // The Open-Meteo geocoder only accepts a single place name, so we search
        // on the city but keep the trailing component (country / state) to
        // disambiguate collisions like Portland OR vs ME, San Jose CR vs CA.
        let parts = destination
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let city = parts.first ?? destination
        let qualifier = parts.count > 1 ? parts.last : nil   // country / state / region

        // Request several candidates so we can pick the one whose country /
        // region matches the qualifier the user supplied, rather than blindly
        // taking the highest-population hit.
        guard let url = Endpoints.OpenMeteo.geocodingURL(name: city, count: qualifier == nil ? 1 : 10) else {
            throw APIError.invalidURL
        }

        // Routed through the shared APIClient. `GeocodingResponse`'s explicit
        // CodingKeys take precedence over the client decoder's snake_case
        // strategy, so decoding is unaffected.
        let response: GeocodingResponse = try await APIClient.shared.get(url: url)
        let results = response.results ?? []
        guard let first = results.first else {
            // Fallback to a default if geocoding fails — the model still gets a generic forecast
            return (lat: 0, lon: 0)
        }

        // Prefer the candidate whose country/admin region matches the qualifier
        // (case-insensitive substring either way, to tolerate "USA" vs
        // "United States" or "OR" vs "Oregon"). Fall back to the first hit.
        let best = bestMatch(in: results, qualifier: qualifier) ?? first
        return (lat: best.latitude, lon: best.longitude)
    }

    /// Chooses the geocoding candidate whose country / admin region best matches
    /// the user-supplied qualifier. Returns nil when there's no qualifier or no
    /// candidate matches, letting the caller fall back to the first result.
    private func bestMatch(in results: [GeocodingResponse.GeoResult], qualifier: String?) -> GeocodingResponse.GeoResult? {
        guard let qualifier, !qualifier.isEmpty else { return nil }
        let needle = qualifier.lowercased()
        return results.first { candidate in
            let haystacks = [candidate.country, candidate.countryCode, candidate.admin1]
                .compactMap { $0?.lowercased() }
            return haystacks.contains { $0.contains(needle) || needle.contains($0) }
        }
    }

    // MARK: - 7-Day Forecast

    private func fetchForecast(lat: Double, lon: Double, days: Int) async throws -> DestinationForecast {
        // Geocoding failed → a generic mild forecast so the list is still useful.
        guard lat != 0 || lon != 0 else {
            return DestinationForecast(avgHighF: 70, avgLowF: 55, rainyDays: 0, snowyDays: 0, dominantCondition: "Partly Cloudy")
        }
        let summary = try await WeatherService.shared.dailyForecast(latitude: lat, longitude: lon, days: days)
        return DestinationForecast(
            avgHighF: summary.avgHighF,
            avgLowF: summary.avgLowF,
            rainyDays: summary.rainyDays,
            snowyDays: summary.snowyDays,
            dominantCondition: summary.dominantCondition
        )
    }

    // MARK: - Activity Extraction

    /// Scans itinerary item titles for known activity keywords.
    /// Also uses NLTagger to surface any notable nouns not covered by keywords.
    private func extractActivities(from trip: Trip) -> [String] {
        let allTitles = trip.items.map { $0.title.lowercased() }.joined(separator: " ")

        var found: [String] = []
        var seen = Set<String>()

        for (keyword, label) in activityKeywords where allTitles.contains(keyword) {
            if seen.insert(label).inserted {
                found.append(label)
            }
        }

        // Add generic labels based on item types
        let hasRestaurants = trip.items.contains { $0.type == .restaurant }
        if hasRestaurants, seen.insert("dining out").inserted {
            found.append("dining out")
        }

        // Use NLTagger to surface any notable nouns from activity items
        let activityTitles = trip.items
            .filter { $0.type == .activity }
            .map { $0.title }
            .joined(separator: ". ")

        if !activityTitles.isEmpty {
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = activityTitles
            let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
            tagger.enumerateTags(in: activityTitles.startIndex..<activityTitles.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
                if tag == .noun {
                    let word = String(activityTitles[range]).lowercased()
                    if word.count > 4, !seen.contains(word) {
                        // Only add if not already covered by a keyword
                        let alreadyCovered = activityKeywords.contains { word.contains($0.keyword) }
                        if !alreadyCovered {
                            seen.insert(word)
                            found.append(word)
                        }
                    }
                }
                return true
            }
        }

        return found.isEmpty ? ["general sightseeing and leisure"] : found
    }

    // MARK: - Airline Detection

    /// Extracts the IATA airline code from flight itinerary items using regex.
    ///
    /// Returns the FIRST well-formed code found (e.g. "B6", "F9"), whether or
    /// not it maps to an entry in `AirlineBaggageRule.rules`. A mapped code lets
    /// us attach concrete allowances; an unmapped code is still worth surfacing
    /// to the model so it knows the actual carrier (basic-economy no-checked-bag
    /// fares differ sharply from full-service carriers) instead of falling back
    /// to a generic "unknown airline" assumption.
    private func detectAirlineIATA(from trip: Trip) -> String? {
        let flightItems = trip.items.filter { $0.type == .flight }
        var firstUnmapped: String?
        for item in flightItems {
            let text = item.title + " " + (item.notes ?? "")
            if let match = text.range(of: #"\b([A-Z]{2})\d{1,4}\b"#, options: .regularExpression) {
                let code = String(text[match].prefix(2))
                if AirlineBaggageRule.rules[code] != nil {
                    return code   // prefer a code we have concrete rules for
                }
                if firstUnmapped == nil { firstUnmapped = code }
            }
        }
        return firstUnmapped
    }

    // MARK: - Prompt Builder

    private func buildPrompt(
        trip: Trip,
        forecast: DestinationForecast,
        activities: [String],
        baggageRule: AirlineBaggageRule?,
        detectedAirlineIATA: String?
    ) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var baggageContext: String
        if let rule = baggageRule {
            let personal = rule.personalItemAllowed ? ", personal item allowed" : ""
            let free = rule.freeBagsIncluded > 0 ? "\(rule.freeBagsIncluded) free checked bag(s)" : "no free checked bags"
            baggageContext = "\(rule.airlineName): carry-on up to \(rule.carryOnWeightKg)kg, \(free)\(personal)"
        } else if let code = detectedAirlineIATA {
            // We recognised the carrier code but have no rule for it — tell the model
            // the actual airline so it can apply its own knowledge (e.g. low-cost
            // carriers whose base fares include no checked bag) rather than
            // defaulting to a generic full-service assumption.
            baggageContext = "Airline IATA code \(code) (no cached baggage rule) — infer typical allowances for this carrier, and if it's a low-cost/basic-economy carrier assume checked bags are NOT included unless purchased"
        } else {
            baggageContext = "Unknown airline — assume standard carry-on and one checked bag"
        }

        return """
        Trip: \(trip.name)
        Destination: \(trip.destination)
        Duration: \(trip.durationInDays) day(s) (\(df.string(from: trip.startDate)) – \(df.string(from: trip.endDate)))
        Weather forecast: \(forecast.summary)
        Activities: \(activities.joined(separator: ", "))
        Airline/baggage: \(baggageContext)

        Generate a practical packing list tailored to this trip. Consider:
        - Weather-appropriate clothing quantities based on duration and forecast
        - Activity-specific gear (e.g. rain jacket if rainy, layers if cold)
        - Baggage limits when recommending quantities
        - Essential documents for international travel if destination appears international
        - Health and safety essentials
        Aim for about \(PackingListGenerator.maxItems) items, most essential first. Be specific with quantities (e.g. 5 socks for 5 days).
        """
    }

    // MARK: - Fallback

    /// Minimal static list used when Apple Intelligence is unavailable or fails before producing anything.
    private func fallbackItems(for forecast: DestinationForecast) -> [SmartPackingItem] {
        var items: [SmartPackingItem] = [
            SmartPackingItem(name: "Passport",            category: .documents),
            SmartPackingItem(name: "Travel insurance",    category: .documents),
            SmartPackingItem(name: "Phone charger",       category: .electronics),
            SmartPackingItem(name: "Medications",         category: .health),
            SmartPackingItem(name: "Toothbrush",          category: .toiletries),
            SmartPackingItem(name: "Deodorant",           category: .toiletries),
            SmartPackingItem(name: "Underwear",           category: .clothing, quantity: 5),
            SmartPackingItem(name: "T-shirts",            category: .clothing, quantity: 4),
            SmartPackingItem(name: "Trousers/Pants",      category: .clothing, quantity: 2),
            SmartPackingItem(name: "Walking shoes",       category: .clothing),
            SmartPackingItem(name: "Snacks",              category: .misc)
        ]
        if forecast.isWet  { items.append(SmartPackingItem(name: "Umbrella / Rain jacket", category: .clothing, notes: "Rainy days expected")) }
        if forecast.isCold { items.append(SmartPackingItem(name: "Warm jacket",            category: .clothing, notes: "Cold weather expected")) }
        if forecast.isHot  { items.append(SmartPackingItem(name: "Sunscreen SPF 50+",      category: .toiletries, notes: "Hot weather expected")) }
        return items
    }
}

// MARK: - Private Response Models

private struct GeocodingResponse: Decodable {
    struct GeoResult: Decodable {
        let latitude: Double
        let longitude: Double
        let name: String
        /// Country name (e.g. "Japan", "United States"), used to disambiguate
        /// same-named cities across countries.
        let country: String?
        /// ISO country code (e.g. "JP", "US").
        let countryCode: String?
        /// Top-level admin region (e.g. "Oregon", "Maine"), used to disambiguate
        /// same-named cities within one country.
        let admin1: String?

        enum CodingKeys: String, CodingKey {
            case latitude, longitude, name, country, admin1
            case countryCode = "country_code"
        }
    }
    let results: [GeoResult]?
}

