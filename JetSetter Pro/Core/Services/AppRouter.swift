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

        // Modal flows already wired into HomeView via NotificationCenter — reuse
        // those routes so we don't duplicate presentation logic.
        case .checkIn:
            selectedTab = .home
            NotificationCenter.default.post(name: .jetSetterInvokeCheckInFlow, object: nil)
        case .disruption:
            selectedTab = .home
            NotificationCenter.default.post(name: .jetSetterOpenDisruption, object: nil)

        // Standalone feature screens — presented by ContentView's sheet host.
        case .flightTracker:   presentedSheet = .flightTracker
        case .documentVault:   presentedSheet = .documentVault
        case .packingList:     presentedSheet = .packingList
        case .groundTransport: presentedSheet = .groundTransport
        case .currency:        presentedSheet = .currency
        }
    }
}

extension Notification.Name {
    /// Posted by the "text my loved ones" intent; Home presents the Messages composer.
    static let jetSetterNotifyLovedOnes = Notification.Name("jetSetterNotifyLovedOnes")
}
