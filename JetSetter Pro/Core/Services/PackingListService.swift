// File: Core/Services/PackingListService.swift
// Generates AI-powered packing lists for Feature 2 using:
//   - Open-Meteo geocoding + 7-day daily forecast for destination weather
//   - Keyword-based activity extraction from itinerary items
//   - Airline baggage rule lookup (20 airlines)
//   - Claude API (claude-sonnet-4-6) for personalized item generation

import Foundation
import NaturalLanguage

// MARK: - Destination Forecast

struct DestinationForecast {
    let avgHighF: Double
    let avgLowF: Double
    let rainyDays: Int
    let snowyDays: Int
    let dominantCondition: String

    /// Human-readable summary passed to Claude as context.
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

    // MARK: - Claude Config

    private enum AnthropicConfig {
        static var apiKey: String { AppSecrets.value(for: .anthropic) ?? "" }
        static let model    = "claude-sonnet-4-6"
        static let endpoint = "https://api.anthropic.com/v1/messages"
    }

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

    /// Full pipeline: geocode → forecast → activity NLP → Claude → parse.
    func generatePackingItems(for trip: Trip) async throws -> [SmartPackingItem] {
        // Step 1: Geocode and fetch forecast (can run while we process NLP)
        let coords = try await geocode(trip.destination)
        let forecastDays = max(1, min(trip.durationInDays, 7))
        let forecast = try await fetchForecast(lat: coords.lat, lon: coords.lon, days: forecastDays)

        // Step 2: Extract activities and detect airline (local, synchronous)
        let activities = extractActivities(from: trip)
        let airlineIATA = detectAirlineIATA(from: trip)
        let baggageRule = airlineIATA.flatMap { AirlineBaggageRule.rules[$0] }

        // Step 3: Build prompt and call Claude
        let prompt = buildClaudePrompt(
            trip: trip,
            forecast: forecast,
            activities: activities,
            baggageRule: baggageRule,
            detectedAirlineIATA: airlineIATA
        )
        return try await callClaude(prompt: prompt, forecast: forecast)
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

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name",     value: city),
            // Request several candidates so we can pick the one whose country /
            // region matches the qualifier the user supplied, rather than blindly
            // taking the highest-population hit.
            URLQueryItem(name: "count",    value: qualifier == nil ? "1" : "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format",   value: "json")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        let results = response.results ?? []
        guard let first = results.first else {
            // Fallback to a default if geocoding fails — Claude will still generate a generic list
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
        // Open-Meteo returns zeros for (0,0) — return a generic mild forecast
        guard lat != 0 || lon != 0 else {
            return DestinationForecast(avgHighF: 70, avgLowF: 55, rainyDays: 0, snowyDays: 0, dominantCondition: "Partly Cloudy")
        }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude",         value: String(lat)),
            URLQueryItem(name: "longitude",        value: String(lon)),
            URLQueryItem(name: "daily",            value: "temperature_2m_max,temperature_2m_min,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "forecast_days",    value: String(days)),
            URLQueryItem(name: "timezone",         value: "auto")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let daily = response.daily

        let avgHigh = daily.temperature2mMax.isEmpty ? 70 : daily.temperature2mMax.reduce(0, +) / Double(daily.temperature2mMax.count)
        let avgLow  = daily.temperature2mMin.isEmpty ? 55 : daily.temperature2mMin.reduce(0, +) / Double(daily.temperature2mMin.count)

        // WMO codes 61–67, 80–82 = rain; 71–77, 85–86 = snow
        let rainyDays = daily.weatherCode.filter { (61...67).contains($0) || (80...82).contains($0) }.count
        let snowyDays = daily.weatherCode.filter { (71...77).contains($0) || (85...86).contains($0) }.count

        // Dominant condition by most frequent code
        let dominant = daily.weatherCode.max(by: { a, b in
            daily.weatherCode.filter { $0 == a }.count < daily.weatherCode.filter { $0 == b }.count
        }).map { WMOWeatherCode.description(for: $0) } ?? "Variable"

        return DestinationForecast(
            avgHighF: avgHigh,
            avgLowF: avgLow,
            rainyDays: rainyDays,
            snowyDays: snowyDays,
            dominantCondition: dominant
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
    /// to Claude so it knows the actual carrier (basic-economy no-checked-bag
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

    // MARK: - Claude Prompt Builder

    private func buildClaudePrompt(
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
            // We recognised the carrier code but have no rule for it — tell Claude
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

        Return ONLY a JSON array — no markdown, no explanation. Each object must have exactly these fields:
        { "name": string, "category": string, "quantity": integer, "notes": string | null }
        Valid category values: Clothing, Toiletries, Electronics, Documents, Health, Misc
        Aim for 25–40 items. Be specific with quantities (e.g. quantity 5 for 5 days of socks).
        """
    }

    // MARK: - Claude API Call

    private func callClaude(prompt: String, forecast: DestinationForecast) async throws -> [SmartPackingItem] {
        // Fail fast with a clear signal when the key isn't configured, rather than
        // sending an empty x-api-key and surfacing a generic 401 → badServerResponse.
        // (Note: an Anthropic key shipped in the client binary is extractable; a
        // backend proxy that holds the key is the recommended production setup.)
        guard !AnthropicConfig.apiKey.isEmpty else {
            return fallbackItems(for: forecast)
        }

        guard let url = URL(string: AnthropicConfig.endpoint) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",        forHTTPHeaderField: "Content-Type")
        req.setValue(AnthropicConfig.apiKey,    forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",              forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": AnthropicConfig.model,
            "max_tokens": 2048,
            "system": "You are a travel packing assistant. You generate precise, practical packing lists in JSON format. You never include markdown formatting or explanations — only raw JSON arrays.",
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = claudeResponse.firstTextContent else {
            throw URLError(.cannotParseResponse)
        }

        return parseClaudeItems(from: text, forecast: forecast)
    }

    // MARK: - Response Parsing

    private func parseClaudeItems(from text: String, forecast: DestinationForecast) -> [SmartPackingItem] {
        // Strip markdown code fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n")
                .dropFirst()
                .joined(separator: "\n")
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let jsonData = cleaned.data(using: .utf8),
              let dtos = try? JSONDecoder().decode([PackingItemDTO].self, from: jsonData)
        else {
            // Claude parse failed — return a minimal fallback list
            return fallbackItems(for: forecast)
        }

        return dtos.map { dto in
            SmartPackingItem(
                name: dto.name,
                category: PackingCategory(rawValue: dto.category) ?? .misc,
                isPacked: false,
                isCustom: false,
                quantity: max(1, dto.quantity),
                notes: dto.notes
            )
        }
    }

    /// Minimal hardcoded fallback if Claude is unavailable or returns unparseable output.
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

private struct ForecastResponse: Decodable {
    let daily: DailyForecast

    struct DailyForecast: Decodable {
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case weatherCode      = "weather_code"
        }
    }
}

// Note: Uses ClaudeResponse + ClaudeContentBlock defined in AssistantModel.swift

/// Intermediate DTO that mirrors Claude's JSON output before mapping to `SmartPackingItem`.
private struct PackingItemDTO: Decodable {
    let name: String
    let category: String
    let quantity: Int
    let notes: String?
}
