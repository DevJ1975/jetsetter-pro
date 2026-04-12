// File: Features/Intelligence/TravelIntelligenceViewModel.swift
// ViewModel for the Proactive Travel Intelligence engine (Feature 6).
// TODO: Full implementation in Feature 6 sprint.
// Key responsibilities: BGProcessingTask setup, signal monitoring (FlightAware,
// WeatherKit, MapKit ETAs, check-in windows), trigger evaluation, card surfacing.

import SwiftUI
import Combine

@MainActor
final class TravelIntelligenceViewModel: ObservableObject {

    /// The single highest-priority proactive card shown at the top of HomeView.
    @Published private(set) var activeCard: ProactiveTrigger? = nil

    /// All recent trigger events (for a history view or debugging).
    @Published private(set) var recentTriggers: [ProactiveTrigger] = []

    @Published private(set) var isMonitoring = false

    func startMonitoring(for trips: [Trip]) {
        guard !isMonitoring else { return }
        isMonitoring = true
        // TODO: Register BGProcessingTask for continuous monitoring
        // TODO: Start CLLocationManager significant location updates
        // TODO: Evaluate all triggers against active trips
    }

    func dismissActiveCard() {
        guard let card = activeCard else { return }
        Task { await logEvent(trigger: card, action: "dismissed") }
        withAnimation { activeCard = nil }
    }

    func actOnCard() {
        guard let card = activeCard else { return }
        if let urlString = card.actionURL, let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
        Task { await logEvent(trigger: card, action: "acted") }
        withAnimation { activeCard = nil }
    }

    // MARK: - Signal Evaluators (stub implementations)

    func evaluateLeaveNow(context: LeaveNowContext, tripId: UUID) {
        // TODO: If minutesUntilLeave <= 60, surface a "Leave Now" card
        // with MapKit ETA and Uber deep link
    }

    func evaluateWeatherChange(destinationCity: String, tripId: UUID) async {
        // TODO: Compare current WeatherKit forecast with 48h-ago forecast
        // Surface card if significant change (rain, extreme cold, etc.)
    }

    func evaluateCheckInWindow(flight: Flight, tripId: UUID) {
        // TODO: Airline-specific check-in open time (usually 24h before departure)
        // Surface card + CheckInService deep link when window opens
    }

    // MARK: - Logging

    private func logEvent(trigger: ProactiveTrigger, action: String) async {
        guard let userId = await SupabaseService.shared.currentUser?.id else { return }
        // TODO: Log IntelligenceEvent to Supabase intelligence_events table
        _ = userId
    }
}
