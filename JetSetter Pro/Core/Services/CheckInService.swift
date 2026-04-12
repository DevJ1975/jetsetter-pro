// File: Core/Services/CheckInService.swift
//
// Resolves airline check-in URLs using:
//   1. Amadeus Flight Check-In Links API (primary)
//   2. Hardcoded fallback dictionary for 20 major airlines
//
// SETUP: Set your Amadeus client ID and secret below.
// Create a free app at https://developers.amadeus.com

import Foundation
import UserNotifications

// MARK: - Amadeus Configuration

private enum AmadeusConfig {
    // TODO: Replace with your Amadeus API credentials
    static let clientID     = "YOUR_AMADEUS_CLIENT_ID"
    static let clientSecret = "YOUR_AMADEUS_CLIENT_SECRET"
    static let tokenURL     = "https://test.api.amadeus.com/v1/security/oauth2/token"
    static let checkInURL   = "https://test.api.amadeus.com/v2/reference-data/urls/checkin-links"
}

// MARK: - CheckInResult

struct CheckInResult {
    let airlineName: String
    let iataCode: String
    let webURL: URL
    let mobileURL: URL?     // Some airlines expose a separate mobile-optimised URL
    let source: CheckInSource
}

enum CheckInSource {
    case amadeus   // Live from Amadeus API
    case fallback  // Hardcoded dictionary
}

// MARK: - CheckInService

/// Resolves airline check-in deep links and schedules check-in-open notifications.
actor CheckInService {

    static let shared = CheckInService()
    private init() {}

    // Cached Amadeus OAuth token and its expiry
    private var amadeusToken: String?
    private var tokenExpiry: Date = .distantPast

    // MARK: - Public API

    /// Returns check-in URL for the given IATA airline code.
    /// Falls back to the hardcoded dictionary if Amadeus is unavailable or unconfigured.
    func checkInResult(for iataCode: String) async -> CheckInResult? {
        let code = iataCode.uppercased()

        // Try Amadeus first (skip if placeholder credentials are still in place)
        if AmadeusConfig.clientID != "YOUR_AMADEUS_CLIENT_ID" {
            if let result = await fetchFromAmadeus(iataCode: code) {
                return result
            }
        }

        // Fall back to hardcoded dictionary
        return fallbackResult(for: code)
    }

    /// Schedules a local notification to fire 24 hours before departure,
    /// reminding the user that check-in is now open.
    func scheduleCheckInNotification(
        airlineName: String,
        flightNumber: String,
        departureDate: Date
    ) async {
        // Check-in typically opens exactly 24 hours before departure
        let checkInOpenTime = departureDate.addingTimeInterval(-24 * 3_600)
        guard checkInOpenTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Check-in open — \(flightNumber)"
        content.body  = "\(airlineName) check-in is now open. Tap to check in and select your seat."
        content.sound = .default
        content.categoryIdentifier = "CHECK_IN_OPEN"
        content.userInfo = ["flightNumber": flightNumber]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: checkInOpenTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "checkin_\(flightNumber)_\(Int(departureDate.timeIntervalSince1970))"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    /// Cancels a previously scheduled check-in notification.
    func cancelCheckInNotification(flightNumber: String, departureDate: Date) {
        let id = "checkin_\(flightNumber)_\(Int(departureDate.timeIntervalSince1970))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Amadeus OAuth + API

    private func fetchAmadeusToken() async throws -> String {
        if let token = amadeusToken, tokenExpiry > Date() { return token }

        guard let url = URL(string: AmadeusConfig.tokenURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=client_credentials&client_id=\(AmadeusConfig.clientID)&client_secret=\(AmadeusConfig.clientSecret)"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)

        struct TokenResponse: Decodable {
            let accessToken: String
            let expiresIn: Int
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn   = "expires_in"
            }
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        amadeusToken = decoded.accessToken
        tokenExpiry  = Date().addingTimeInterval(Double(decoded.expiresIn) - 60)
        return decoded.accessToken
    }

    private func fetchFromAmadeus(iataCode: String) async -> CheckInResult? {
        do {
            let token = try await fetchAmadeusToken()

            var comps = URLComponents(string: AmadeusConfig.checkInURL)!
            comps.queryItems = [
                URLQueryItem(name: "airlineCode", value: iataCode),
                URLQueryItem(name: "language",    value: "EN-US")
            ]
            guard let url = comps.url else { return nil }

            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }

            // Amadeus response: { "data": [ { "type": "checkin-link", "id": "...", "href": "...", "channel": "Mobile"|"Web"|"All" } ] }
            struct AmadeusLink: Decodable {
                let href: String
                let channel: String
            }
            struct AmadeusResponse: Decodable {
                let data: [AmadeusLink]
            }

            let decoded = try JSONDecoder().decode(AmadeusResponse.self, from: data)
            guard !decoded.data.isEmpty else { return nil }

            let webLink    = decoded.data.first { $0.channel == "Web" || $0.channel == "All" }
            let mobileLink = decoded.data.first { $0.channel == "Mobile" }

            guard let webHref = webLink?.href, let webURL = URL(string: webHref) else { return nil }
            let mobileURL = mobileLink.flatMap { URL(string: $0.href) }

            let name = fallbackAirlines[iataCode]?.name ?? iataCode
            return CheckInResult(
                airlineName: name,
                iataCode: iataCode,
                webURL: webURL,
                mobileURL: mobileURL,
                source: .amadeus
            )
        } catch {
            return nil
        }
    }

    // MARK: - Fallback Dictionary

    struct FallbackEntry {
        let name: String
        let webURLString: String
    }

    /// Hardcoded check-in URLs for the top 20 US and international airlines.
    /// Updated April 2026 — verify these periodically as airlines may change URLs.
    private let fallbackAirlines: [String: FallbackEntry] = [
        // US Carriers
        "UA": FallbackEntry(name: "United Airlines",        webURLString: "https://www.united.com/en/us/checkin"),
        "DL": FallbackEntry(name: "Delta Air Lines",        webURLString: "https://www.delta.com/us/en/check-in/overview"),
        "AA": FallbackEntry(name: "American Airlines",      webURLString: "https://www.aa.com/checkin/viewCheckinPage"),
        "WN": FallbackEntry(name: "Southwest Airlines",     webURLString: "https://www.southwest.com/air/check-in/"),
        "B6": FallbackEntry(name: "JetBlue",                webURLString: "https://checkin.jetblue.com/"),
        "AS": FallbackEntry(name: "Alaska Airlines",        webURLString: "https://www.alaskaair.com/checkin"),
        "NK": FallbackEntry(name: "Spirit Airlines",        webURLString: "https://www.spirit.com/CheckIn"),
        "F9": FallbackEntry(name: "Frontier Airlines",      webURLString: "https://www.flyfrontier.com/travel/travel-info/check-in/"),
        "HA": FallbackEntry(name: "Hawaiian Airlines",      webURLString: "https://www.hawaiianairlines.com/my-trips/check-in"),
        "G4": FallbackEntry(name: "Allegiant Air",          webURLString: "https://www.allegiantair.com/online-check-in"),
        // International Carriers
        "BA": FallbackEntry(name: "British Airways",        webURLString: "https://www.britishairways.com/travel/olcilandingpageauthreq/public/en_gb"),
        "AF": FallbackEntry(name: "Air France",             webURLString: "https://checkin.airfrance.com/"),
        "LH": FallbackEntry(name: "Lufthansa",              webURLString: "https://www.lufthansa.com/us/en/online-check-in"),
        "EK": FallbackEntry(name: "Emirates",               webURLString: "https://www.emirates.com/english/manage/online-check-in/"),
        "QR": FallbackEntry(name: "Qatar Airways",          webURLString: "https://www.qatarairways.com/en/check-in.html"),
        "AC": FallbackEntry(name: "Air Canada",             webURLString: "https://www.aircanada.com/us/en/aco/home/fly/check-in.html"),
        "WS": FallbackEntry(name: "WestJet",                webURLString: "https://www.westjet.com/en-ca/check-in"),
        "LA": FallbackEntry(name: "LATAM Airlines",         webURLString: "https://www.latamairlines.com/us/en/experience/prepare-your-trip/check-in"),
        "AV": FallbackEntry(name: "Avianca",                webURLString: "https://www.avianca.com/us/en/prepare-your-trip/at-the-airport/check-in/"),
        "KL": FallbackEntry(name: "KLM Royal Dutch Airlines", webURLString: "https://www.klm.com/us/en/travel-information/check-in/online-check-in")
    ]

    private func fallbackResult(for iataCode: String) -> CheckInResult? {
        guard let entry = fallbackAirlines[iataCode],
              let url = URL(string: entry.webURLString) else { return nil }
        return CheckInResult(
            airlineName: entry.name,
            iataCode: iataCode,
            webURL: url,
            mobileURL: nil,
            source: .fallback
        )
    }
}
