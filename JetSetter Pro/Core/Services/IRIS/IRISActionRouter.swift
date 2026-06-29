// File: Core/Services/IRIS/IRISActionRouter.swift
//
// The bridge that lets IRIS *drive* the app instead of only describing it.
// IRIS tools call into this router to:
//   • navigate — switch tabs or present a feature screen (non-destructive,
//     runs immediately)
//   • stage a write — park an `IRISPendingAction` that the chat surfaces as a
//     confirmation card; the actual mutation only runs when the user approves.
//
// It reuses the app's existing NotificationCenter routing (the same events the
// NotificationManager posts and HomeView already listens for) for the modal
// flows that are wired into Home, and a router-owned sheet for the rest.

import Foundation
import SwiftUI
import Combine

@MainActor
final class IRISActionRouter: ObservableObject {

    static let shared = IRISActionRouter()
    private init() {}

    // MARK: - Tabs

    /// Mirrors the tab order declared in `ContentView.mainTabView`.
    enum Tab: Int, Hashable, CaseIterable {
        case home, itinerary, iris, expenses, more
    }

    /// Feature screens IRIS can present modally over the current tab.
    enum Sheet: String, Identifiable, Hashable, CaseIterable {
        case flightTracker, documentVault, packingList, groundTransport, currency
        var id: String { rawValue }
    }

    @Published var selectedTab: Tab = .home
    @Published var presentedSheet: Sheet?

    /// A write that IRIS has prepared but NOT committed. The chat renders this
    /// as a confirmation card; commit happens only on user approval.
    @Published var pendingAction: IRISPendingAction?

    // MARK: - Navigation

    /// Every place IRIS can take the user. Raw values double as the vocabulary
    /// the navigation tool maps free-text screen names onto.
    enum Destination: String, CaseIterable, Sendable {
        // Tab roots
        case home, itinerary, iris, expenses, more
        // Modal feature flows
        case checkIn, disruption, flightTracker, documentVault, packingList, groundTransport, currency
    }

    /// Switches tabs and/or presents the matching screen. Non-destructive, so
    /// it executes immediately without a confirmation card.
    func navigate(to destination: Destination) {
        switch destination {
        // Tab roots
        case .home:      selectedTab = .home
        case .itinerary: selectedTab = .itinerary
        case .iris:      selectedTab = .iris
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
        case .flightTracker:  presentedSheet = .flightTracker
        case .documentVault:  presentedSheet = .documentVault
        case .packingList:    presentedSheet = .packingList
        case .groundTransport: presentedSheet = .groundTransport
        case .currency:       presentedSheet = .currency
        }
    }

    // MARK: - Actions

    /// Stage a write for user confirmation. Replaces any prior pending action.
    func proposeAction(_ action: IRISPendingAction) {
        pendingAction = action
    }

    func cancelPendingAction() {
        pendingAction = nil
    }
}

// MARK: - Pending Action

/// A confirm-before-commit unit of work. IRIS tools build one of these and hand
/// it to the router; the `commit` closure performs the real mutation and returns
/// a human-readable result line for IRIS to read back.
struct IRISPendingAction: Identifiable {

    enum Kind: String {
        case logExpense
        case checkIn
        case addTrip
        case trackFlight
        case generatePackingList
        case submitExpenses
    }

    let id = UUID()
    let kind: Kind
    /// Short, human-readable summary shown on the confirmation card,
    /// e.g. "Log $45.20 at Hertz (USD)".
    let summary: String
    /// Performs the actual write and returns a result line to speak/show.
    let commit: @MainActor () async -> String

    init(kind: Kind, summary: String, commit: @escaping @MainActor () async -> String) {
        self.kind = kind
        self.summary = summary
        self.commit = commit
    }
}
