// File: Core/Services/AppRouter.swift
//
// Single place that switches tabs and presents feature screens on request from
// App Intents (Siri, Shortcuts, Spotlight), notification taps, and the
// proactive suggestion cards. Non-destructive by design: every route here is a
// navigation, never a write.

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppRouter {

    static let shared = AppRouter()
    private init() {}

    // MARK: - Tabs

    /// Mirrors the tab order declared in `ContentView.mainTabView`.
    enum Tab: Int, Hashable, CaseIterable {
        case home, itinerary, assistant, expenses, more
    }

    /// Feature screens that can be presented modally over the current tab.
    enum Sheet: String, Identifiable, Hashable, CaseIterable {
        case flightTracker, documentVault, packingList, groundTransport, currency
        var id: String { rawValue }
    }

    var selectedTab: Tab = .home
    var presentedSheet: Sheet?

    /// An action a screen should perform once it's on screen. Set by App
    /// Intents and deep routes, consumed (and cleared) by the destination view
    /// in its `.task`/`.onChange`, so a cold launch from Siri can't lose it the
    /// way a NotificationCenter post to an unmounted view would.
    enum PendingAction: Equatable {
        case checkIn
        case disruption
        case generatePackingList(tripID: UUID?)
        case notifyLovedOnes(LovedOnesEvent)
    }
    var pendingAction: PendingAction?

    /// Clears `pendingAction` if it equals `action` (so a stale consumer can't
    /// wipe a newer request).
    func consume(_ action: PendingAction) {
        if pendingAction == action { pendingAction = nil }
    }

    // MARK: - Navigation

    /// Every place the app can be routed to.
    enum Destination: String, CaseIterable, Sendable {
        // Tab roots
        case home, itinerary, assistant, expenses, more
        // Modal feature flows
        case checkIn, disruption, flightTracker, documentVault, packingList, groundTransport, currency
    }

    /// Switches tabs and/or presents the matching screen.
    func navigate(to destination: Destination) {
        switch destination {
        case .home:      selectedTab = .home
        case .itinerary: selectedTab = .itinerary
        case .assistant: selectedTab = .assistant
        case .expenses:  selectedTab = .expenses
        case .more:      selectedTab = .more

        // Modal flows hosted by HomeView: hand it a pending action it consumes
        // once mounted (works on cold launch), rather than posting a notification
        // that has no subscriber yet.
        case .checkIn:
            selectedTab = .home
            pendingAction = .checkIn
        case .disruption:
            selectedTab = .home
            pendingAction = .disruption

        // Standalone feature screens — presented by ContentView's sheet host.
        case .flightTracker:   presentedSheet = .flightTracker
        case .documentVault:   presentedSheet = .documentVault
        case .packingList:     presentedSheet = .packingList
        case .groundTransport: presentedSheet = .groundTransport
        case .currency:        presentedSheet = .currency
        }
    }
}


