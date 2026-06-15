// File: Features/Intelligence/TravelIntelligenceViewModel.swift
// Evaluates local trip data to surface a single proactive card on Home.
// Three signals (highest priority first):
//   1. Flight imminent — < 4h to departure
//   2. Check-in window open — 12h to 24h before departure
//   3. Trip starting soon — < 48h to first flight of a trip, no other card active
//
// MVP: pure-local evaluation, no background tasks, no remote services. Re-runs
// whenever HomeView surfaces and once per minute while it's visible.

import SwiftUI
import Combine

extension Notification.Name {
    /// Posted when a Travel Intelligence check-in card is tapped. HomeView
    /// presents the in-app CheckInFlowView in response.
    static let jetSetterInvokeCheckInFlow = Notification.Name("jetSetterInvokeCheckInFlow")
}

@MainActor
final class TravelIntelligenceViewModel: ObservableObject {

    @Published private(set) var activeCard: ProactiveTrigger? = nil
    @Published private(set) var recentTriggers: [ProactiveTrigger] = []

    /// Trigger keys (type + flight identifier) the user has dismissed this session.
    /// We don't re-surface dismissed cards until conditions change materially.
    private var dismissedKeys: Set<String> = []

    private var refreshTask: Task<Void, Never>?

    deinit { refreshTask?.cancel() }

    // MARK: - Public API

    /// Re-evaluates all signals against the supplied trips and updates `activeCard`.
    /// Safe to call repeatedly; idempotent.
    func evaluate(trips: [Trip], now: Date = Date()) {
        let candidates = [
            evaluateImminentFlight(trips: trips, now: now),
            evaluateCheckInWindow(trips: trips, now: now),
            evaluateTripStartingSoon(trips: trips, now: now)
        ].compactMap { $0 }

        let next = candidates.first { !dismissedKeys.contains(dismissKey(for: $0)) }

        if next?.id != activeCard?.id {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                activeCard = next
            }
        }
    }

    /// Starts a 60-second timer that re-evaluates while HomeView is on screen.
    func startAutoRefresh(trips: @escaping () -> [Trip]) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.evaluate(trips: trips())
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Card actions

    func dismissActiveCard() {
        guard let card = activeCard else { return }
        dismissedKeys.insert(dismissKey(for: card))
        recentTriggers.append(card)
        withAnimation { activeCard = nil }
    }

    func actOnCard() {
        guard let card = activeCard else { return }
        // Check-in cards must launch the in-app CheckInFlowView (seat map +
        // embedded boarding pass with QR), not an external airline URL that
        // 404s for synthetic demo flight numbers.
        if card.type == .checkInOpen {
            NotificationCenter.default.post(name: .jetSetterInvokeCheckInFlow, object: nil)
        } else if let urlString = card.actionURL, let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
        dismissedKeys.insert(dismissKey(for: card))
        recentTriggers.append(card)
        withAnimation { activeCard = nil }
    }

    // MARK: - Signal Evaluators

    /// Returns a "Leave for the airport" card when a flight is < 4h away.
    /// Also fires an urgent ding (once per flight) when the window is < 90 min
    /// and the user hasn't yet checked in.
    private func evaluateImminentFlight(trips: [Trip], now: Date) -> ProactiveTrigger? {
        guard let (item, _) = nextFlight(in: trips, after: now) else { return nil }
        let minutes = Int(item.startDate.timeIntervalSince(now) / 60)
        guard minutes > 0, minutes <= 240 else { return nil }

        let flightId = extractFlightNumber(from: item.title) ?? "your flight"
        let originIATA = extractOriginIATA(from: item.location)
        let notCheckedIn = !CheckInStateStore.isCheckedIn(
            flightNumber: flightId,
            departure: item.startDate
        )

        let title: String
        let body: String
        if minutes <= 90 {
            title = notCheckedIn
                ? "Gate closing — check in for \(flightId)"
                : "Leave Now — \(flightId)"
            body = notCheckedIn
                ? "Departs in \(formatMinutes(minutes)) and you haven't checked in. Open the airline to check in now."
                : "Departs in \(formatMinutes(minutes)). Tap for directions to \(originIATA ?? "the airport")."

            // Play the gate-closing ding once per flight when the user
            // hasn't checked in yet.
            if notCheckedIn {
                AudioAlertService.shared.playOnce(
                    key: "gate_closing_\(flightId)_\(Int(item.startDate.timeIntervalSince1970))",
                    kind: .gateClosing
                )
            }
        } else {
            title = "Heads up — \(flightId) departs soon"
            body = "Boarding in \(formatMinutes(minutes)). Check traffic to \(originIATA ?? "the airport")."
        }

        let mapsURL = originIATA.flatMap { mapsDirectionsURL(toAirport: $0) }

        return ProactiveTrigger(
            id: UUID(),
            type: .leaveNow,
            title: title,
            body: body,
            actionLabel: mapsURL != nil ? "Directions" : nil,
            actionURL: mapsURL?.absoluteString,
            firedAt: now
        )
    }

    /// Returns a "Check-in is open" card when a flight is 12–24h out.
    private func evaluateCheckInWindow(trips: [Trip], now: Date) -> ProactiveTrigger? {
        guard let (item, _) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 12, hours <= 24 else { return nil }

        let flightId = extractFlightNumber(from: item.title) ?? "your flight"
        let iata = extractAirlineCode(from: flightId)
        let url = iata.flatMap { checkInURL(forAirlineIATA: $0) }

        return ProactiveTrigger(
            id: UUID(),
            type: .checkInOpen,
            title: "Check-in is open",
            body: "Check in for \(flightId) now to lock in your seat.",
            actionLabel: url != nil ? "Check In" : nil,
            actionURL: url?.absoluteString,
            firedAt: now
        )
    }

    /// Returns a "Trip starts soon" card 24–48h before the first flight of a trip.
    /// Lower priority than the two flight-specific cards.
    private func evaluateTripStartingSoon(trips: [Trip], now: Date) -> ProactiveTrigger? {
        let upcomingTrips = trips
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }

        guard let trip = upcomingTrips.first else { return nil }
        let hours = trip.startDate.timeIntervalSince(now) / 3600
        guard hours > 24, hours <= 48 else { return nil }

        return ProactiveTrigger(
            id: UUID(),
            type: .tripStartingSoon,
            title: "\(trip.destination) in \(Int(hours))h",
            body: "Your trip starts soon. Tap to review packing and itinerary.",
            actionLabel: nil,
            actionURL: nil,
            firedAt: now
        )
    }

    // MARK: - Helpers

    private func nextFlight(in trips: [Trip], after now: Date) -> (ItineraryItem, Trip)? {
        let candidates = trips.flatMap { trip in
            trip.items
                .filter { $0.type == .flight && $0.startDate > now }
                .map { (item: $0, trip: trip) }
        }
        return candidates
            .min(by: { $0.item.startDate < $1.item.startDate })
            .map { ($0.item, $0.trip) }
    }

    /// Pulls a flight number like "UA837" from "Flight UA837" / "UA 837 to NRT".
    private func extractFlightNumber(from title: String) -> String? {
        let normalized = title.replacingOccurrences(
            of: #"([A-Z]{2,3})\s+(\d)"#,
            with: "$1$2",
            options: .regularExpression
        )
        guard let range = normalized.range(of: #"\b[A-Z]{2,3}\d{1,4}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(normalized[range])
    }

    private func extractAirlineCode(from flightNumber: String) -> String? {
        guard let range = flightNumber.range(of: #"^[A-Z]{2,3}"#, options: .regularExpression) else {
            return nil
        }
        return String(flightNumber[range])
    }

    /// Pulls "SFO" out of "SFO → NRT" or returns nil.
    private func extractOriginIATA(from location: String?) -> String? {
        guard let location else { return nil }
        let parts = location.components(separatedBy: " → ")
        guard let first = parts.first?.trimmingCharacters(in: .whitespaces),
              first.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil
        else { return nil }
        return first
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func mapsDirectionsURL(toAirport iata: String) -> URL? {
        // Apple Maps web URL works as deep link and falls back to web on Mac.
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "daddr", value: "\(iata) Airport")]
        return components?.url
    }

    /// A small fallback dictionary of the most common US/international carriers.
    /// CheckInService has the canonical full list — kept short here for MVP.
    private func checkInURL(forAirlineIATA iata: String) -> URL? {
        let map: [String: String] = [
            "UA": "https://www.united.com/en/us/checkin",
            "DL": "https://www.delta.com/us/en/check-in/overview",
            "AA": "https://www.aa.com/checkin/viewCheckinPage",
            "WN": "https://www.southwest.com/air/check-in/",
            "B6": "https://checkin.jetblue.com/",
            "AS": "https://www.alaskaair.com/checkin",
            "BA": "https://www.britishairways.com/travel/olcilandingpageauthreq/public/en_gb",
            "AF": "https://checkin.airfrance.com/",
            "LH": "https://www.lufthansa.com/us/en/online-check-in",
            "EK": "https://www.emirates.com/english/manage/online-check-in/",
            "QR": "https://www.qatarairways.com/en/check-in.html",
            "AC": "https://www.aircanada.com/us/en/aco/home/fly/check-in.html",
            "JL": "https://www.jal.co.jp/jp/en/inter/checkin/",
            "NH": "https://www.ana.co.jp/en/us/plan-book/checkin/"
        ]
        return map[iata].flatMap(URL.init(string:))
    }

    /// A dismissal is bucketed by trigger type + flight identifier so a fresh
    /// signal on a different flight surfaces a new card.
    private func dismissKey(for trigger: ProactiveTrigger) -> String {
        let suffix = trigger.title
        return "\(trigger.type.rawValue):\(suffix)"
    }
}
