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

extension Notification.Name {
    /// Posted when a Travel Intelligence check-in card is tapped. HomeView
    /// presents the in-app CheckInFlowView in response.
    static let jetSetterInvokeCheckInFlow = Notification.Name("jetSetterInvokeCheckInFlow")
}

@MainActor
@Observable
final class TravelIntelligenceViewModel {

    private(set) var activeCard: ProactiveTrigger? = nil
    private(set) var recentTriggers: [ProactiveTrigger] = []

    /// Most recent triggers to keep — bounds `recentTriggers` so a long-running
    /// session can't grow it without bound.
    private let recentTriggersCap = 25

    /// Trigger keys (type + flight identifier) the user has dismissed, mapped to
    /// the moment the dismissal stops being authoritative (the flight's departure,
    /// or a bounded fallback). Persisted to `UserDefaults` so a dismissal survives
    /// relaunch — a card the user swiped away must not reappear on a cold start —
    /// and pruned once the underlying event has passed so keys can't accumulate.
    @ObservationIgnored private var dismissedKeys: [String: Date] = [:]

    /// Fallback lifetime for a dismissal whose identifier carries no parseable
    /// departure timestamp (e.g. a `tripStartingSoon` bucket).
    private let dismissalRetention: TimeInterval = 48 * 60 * 60

    private let dismissalStorageKey = "jetsetter_intelligence_dismissed_keys"

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        loadDismissedKeys()
    }

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

        pruneDismissedKeys(now: now)
        let next = candidates.first { dismissedKeys[dismissKey(for: $0)] == nil }

        // Fire the gate-closing ding only for a card the user will actually see
        // (survived the dismissedKeys filter). Tied to the card here rather than
        // inside the pure evaluator so a dismissed card never dings. `playOnce`
        // still dedupes to a single ding per flight.
        if let next, let key = gateClosingAlertKey(for: next) {
            AudioAlertService.shared.playOnce(key: key, kind: .gateClosing)
        }

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
                try? await Task.sleep(for: .seconds(60))
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
        recordDismissal(of: card)
        appendRecent(card)
        withAnimation { activeCard = nil }
    }

    /// In-app web target for a card action URL (§7.7 — presented via `.inAppWeb`).
    var externalWebURL: URL?

    func actOnCard() {
        guard let card = activeCard else { return }
        // Check-in cards must launch the in-app CheckInFlowView (seat map +
        // embedded boarding pass with QR), not an external airline URL that
        // 404s for synthetic demo flight numbers.
        if card.type == .checkInOpen {
            NotificationCenter.default.post(name: .jetSetterInvokeCheckInFlow, object: nil)
        } else if let urlString = card.actionURL, let url = URL(string: urlString) {
            externalWebURL = url   // present in-app (§7.7)
        }
        recordDismissal(of: card)
        appendRecent(card)
        withAnimation { activeCard = nil }
    }

    /// Appends to the recent-actions log, keeping only the newest `recentTriggersCap`.
    private func appendRecent(_ card: ProactiveTrigger) {
        recentTriggers.append(card)
        if recentTriggers.count > recentTriggersCap {
            recentTriggers.removeFirst(recentTriggers.count - recentTriggersCap)
        }
    }

    // MARK: - Dismissal persistence

    /// Records a dismissal and persists it, using the trigger's departure
    /// timestamp (encoded in `dismissIdentifier` as "id@epoch") as the expiry so
    /// the suppression naturally lapses once the flight/trip has passed. Falls
    /// back to a bounded retention window when no timestamp is available.
    private func recordDismissal(of card: ProactiveTrigger, now: Date = Date()) {
        let key = dismissKey(for: card)
        dismissedKeys[key] = dismissalExpiry(for: card, now: now)
        persistDismissedKeys()
    }

    private func dismissalExpiry(for card: ProactiveTrigger, now: Date) -> Date {
        if let identifier = card.dismissIdentifier,
           let epochString = identifier.components(separatedBy: "@").last,
           let epoch = TimeInterval(epochString) {
            return Date(timeIntervalSince1970: epoch)
        }
        return now.addingTimeInterval(dismissalRetention)
    }

    /// Drops dismissals whose event has passed so the store can't accumulate and
    /// a reused key eventually stops suppressing a genuinely new card.
    private func pruneDismissedKeys(now: Date) {
        let before = dismissedKeys.count
        dismissedKeys = dismissedKeys.filter { $0.value > now }
        if dismissedKeys.count != before { persistDismissedKeys() }
    }

    private func loadDismissedKeys() {
        guard let raw = UserDefaults.standard.dictionary(forKey: dismissalStorageKey) as? [String: Double] else { return }
        let now = Date()
        dismissedKeys = raw.reduce(into: [:]) { result, entry in
            let date = Date(timeIntervalSince1970: entry.value)
            if date > now { result[entry.key] = date }
        }
        if dismissedKeys.count != raw.count { persistDismissedKeys() }
    }

    private func persistDismissedKeys() {
        let encoded = dismissedKeys.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(encoded, forKey: dismissalStorageKey)
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
            // NOTE: the gate-closing ding is fired in `evaluate()` after the
            // dismissedKeys filter, so a dismissed card never dings. See
            // `gateClosingAlertKey(for:)`.
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
            firedAt: now,
            dismissIdentifier: "\(flightId)@\(Int(item.startDate.timeIntervalSince1970))"
        )
    }

    /// Returns a "Check-in is open" card when a flight is 4–24h out. The lower
    /// bound meets the imminent-flight evaluator (< 4h) so coverage is continuous
    /// down to departure; check-in typically stays open until ~1h before.
    private func evaluateCheckInWindow(trips: [Trip], now: Date) -> ProactiveTrigger? {
        guard let (item, _) = nextFlight(in: trips, after: now) else { return nil }
        let hours = item.startDate.timeIntervalSince(now) / 3600
        guard hours > 4, hours <= 24 else { return nil }

        let flightId = extractFlightNumber(from: item.title) ?? "your flight"

        // The "Check In" button always invokes the in-app CheckInFlowView via
        // NotificationCenter (see `actOnCard`), which works for any carrier. So
        // its visibility must NOT depend on the per-airline external URL lookup —
        // we always surface the CTA and leave actionURL nil for this card type.
        return ProactiveTrigger(
            id: UUID(),
            type: .checkInOpen,
            title: "Check-in is open",
            body: "Check in for \(flightId) now to lock in your seat.",
            actionLabel: "Check In",
            actionURL: nil,
            firedAt: now,
            dismissIdentifier: "\(flightId)@\(Int(item.startDate.timeIntervalSince1970))"
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
            title: "\(trip.destination) in \(Int(hours.rounded()))h",
            body: "Your trip starts soon. Tap to review packing and itinerary.",
            actionLabel: nil,
            actionURL: nil,
            firedAt: now,
            dismissIdentifier: "\(trip.destination)@\(Int(trip.startDate.timeIntervalSince1970))"
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

    /// A dismissal is bucketed by trigger type + a stable per-signal identifier
    /// (flight / trip) so a fresh signal on a different flight surfaces a new card,
    /// while a dismissed card stays dismissed as its time-varying title changes.
    /// Falls back to the title only for triggers that don't carry an identifier.
    private func dismissKey(for trigger: ProactiveTrigger) -> String {
        let suffix = trigger.dismissIdentifier ?? trigger.title
        return "\(trigger.type.rawValue):\(suffix)"
    }

    /// The `AudioAlertService` dedup key for a gate-closing ding, or nil when the
    /// trigger isn't a gate-closing (imminent + not-checked-in) card. Rebuilt from
    /// the trigger's `dismissIdentifier` ("flightId@epoch") so the key stays stable
    /// per flight and dedupes across evaluations, matching the original scheme.
    private func gateClosingAlertKey(for trigger: ProactiveTrigger) -> String? {
        guard trigger.type == .leaveNow,
              trigger.title.hasPrefix("Gate closing"),
              let identifier = trigger.dismissIdentifier
        else { return nil }
        let parts = identifier.components(separatedBy: "@")
        guard parts.count == 2 else { return nil }
        return "gate_closing_\(parts[0])_\(parts[1])"
    }
}
