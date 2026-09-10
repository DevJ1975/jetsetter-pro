// File: Core/Services/CheckInService.swift
//
// Resolves airline check-in URLs from a curated table of 20 major airlines,
// with a web-search link as the last resort so the UI never dead-ends. No
// partner API is involved.

import Foundation
import UserNotifications

// MARK: - CheckInResult

struct CheckInResult {
    let airlineName: String
    let iataCode: String
    let webURL: URL
    let mobileURL: URL?     // Some airlines expose a separate mobile-optimised URL
    let source: CheckInSource
}

enum CheckInSource {
    case fallback  // Curated dictionary or web-search link
}

// MARK: - CheckInService

/// Resolves airline check-in deep links and schedules check-in-open notifications.
actor CheckInService {

    static let shared = CheckInService()
    private init() {}

    // MARK: - Public API

    /// Returns the check-in URL for the given IATA airline code: the curated
    /// dictionary first, then a web-search link so the UI never dead-ends.
    func checkInResult(for iataCode: String) async -> CheckInResult? {
        let code = iataCode.uppercased()
        return fallbackResult(for: code) ?? searchFallbackResult(for: code)
    }

    /// Schedules a local notification to fire when the carrier's online
    /// check-in window opens, reminding the user that check-in is now open.
    func scheduleCheckInNotification(
        airlineName: String,
        flightNumber: String,
        departureDate: Date
    ) async {
        // Check-in does not universally open at T-24h — several international
        // carriers open earlier. Use the carrier's known lead time (defaulting
        // to 24h) so the reminder isn't hours late for those airlines.
        let leadHours = checkInLeadHours(forAirlineNamed: airlineName)
        let checkInOpenTime = departureDate.addingTimeInterval(-leadHours * 3_600)
        guard checkInOpenTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Check-in open — \(flightNumber)"
        content.body  = "\(airlineName) check-in is now open. Tap to check in and select your seat."
        content.sound = .default
        content.categoryIdentifier = "CHECK_IN_OPEN"
        content.userInfo = ["flightNumber": flightNumber]

        // Fire at a fixed instant so the reminder stays correct even if the
        // traveler changes timezones between scheduling and departure. A
        // calendar trigger would capture wall-clock components in the current
        // device timezone and misfire after a timezone change.
        let interval = checkInOpenTime.timeIntervalSinceNow
        guard interval > 0 else { return }
        guard await NotificationManager.shared.ensureAuthorized() else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let id = "checkin_\(flightNumber.uppercased())_\(Int(departureDate.timeIntervalSince1970))"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    /// Cancels a previously scheduled check-in notification.
    func cancelCheckInNotification(flightNumber: String, departureDate: Date) {
        let id = "checkin_\(flightNumber.uppercased())_\(Int(departureDate.timeIntervalSince1970))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Fallback Dictionary

    struct FallbackEntry {
        let name: String
        let webURLString: String
        /// Hours before departure that this carrier's online check-in opens.
        /// Check-in does NOT universally open at T-24h: many international
        /// carriers open earlier (Emirates/Qatar/Lufthansa ~48h). Defaults to
        /// 24h via the initializer when a carrier's window is unknown.
        let checkInLeadHours: Double

        init(name: String, webURLString: String, checkInLeadHours: Double = 24) {
            self.name = name
            self.webURLString = webURLString
            self.checkInLeadHours = checkInLeadHours
        }
    }

    /// Hardcoded check-in URLs for the top 20 US and international airlines.
    /// Updated April 2026 — verify these periodically as airlines may change URLs.
    private let fallbackAirlines: [String: FallbackEntry] = [
        // US Carriers — nearly all open at T-24h.
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
        // International Carriers — several open earlier than 24h.
        "BA": FallbackEntry(name: "British Airways",        webURLString: "https://www.britishairways.com/travel/olcilandingpageauthreq/public/en_gb"),
        "AF": FallbackEntry(name: "Air France",             webURLString: "https://checkin.airfrance.com/",                       checkInLeadHours: 30),
        "LH": FallbackEntry(name: "Lufthansa",              webURLString: "https://www.lufthansa.com/us/en/online-check-in",       checkInLeadHours: 23),
        "EK": FallbackEntry(name: "Emirates",               webURLString: "https://www.emirates.com/english/manage/online-check-in/", checkInLeadHours: 48),
        "QR": FallbackEntry(name: "Qatar Airways",          webURLString: "https://www.qatarairways.com/en/check-in.html",         checkInLeadHours: 48),
        "AC": FallbackEntry(name: "Air Canada",             webURLString: "https://www.aircanada.com/us/en/aco/home/fly/check-in.html"),
        "WS": FallbackEntry(name: "WestJet",                webURLString: "https://www.westjet.com/en-ca/check-in"),
        "LA": FallbackEntry(name: "LATAM Airlines",         webURLString: "https://www.latamairlines.com/us/en/experience/prepare-your-trip/check-in", checkInLeadHours: 48),
        "AV": FallbackEntry(name: "Avianca",                webURLString: "https://www.avianca.com/us/en/prepare-your-trip/at-the-airport/check-in/"),
        "KL": FallbackEntry(name: "KLM Royal Dutch Airlines", webURLString: "https://www.klm.com/us/en/travel-information/check-in/online-check-in", checkInLeadHours: 30)
    ]

    /// Lead hours before departure that the named airline's check-in opens.
    /// Looked up by display name (the scheduling API only receives the name,
    /// not the IATA code). Defaults to 24h when the carrier is unknown.
    private func checkInLeadHours(forAirlineNamed name: String) -> Double {
        let target = name.lowercased()
        return fallbackAirlines.values
            .first { $0.name.lowercased() == target }?
            .checkInLeadHours ?? 24
    }

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

    /// Last-resort result for carriers outside the dictionary. Rather than
    /// dead-ending the UI at "unavailable",
    /// hand the user an actionable web search for the airline's check-in page.
    private func searchFallbackResult(for iataCode: String) -> CheckInResult? {
        let query = "\(iataCode) airline online check in"
        var comps = URLComponents(string: "https://www.google.com/search")
        comps?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = comps?.url else { return nil }
        return CheckInResult(
            airlineName: iataCode,
            iataCode: iataCode,
            webURL: url,
            mobileURL: nil,
            source: .fallback
        )
    }
}
