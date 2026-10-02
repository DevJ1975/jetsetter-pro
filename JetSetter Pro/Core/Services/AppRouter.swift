// File: Core/Services/AppRouter.swift
//
// Single place that switches tabs and presents feature screens on request from
// App Intents (Siri, Shortcuts, Spotlight), notification taps, `jetsetterpro://`
// links, the Live Activity, and the proactive suggestion cards.
// Non-destructive by design: every route here is a navigation, never a write.
//
// Requests from outside the current screen (a URL, a notification, a Live
// Activity button) go through `open(_:)`, which first asks every presented
// modal to close. Before that, a notification tapped while a sheet was up
// switched tabs underneath the sheet, so the tap seemed to do nothing.
//
// Screens that need to act once they're on screen get a `pendingAction`,
// consumed in their `.task`, so a cold launch can't lose it.

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
        case home, itinerary, wallet, expenses, more
    }

    /// Feature screens that can be presented modally over the current tab.
    enum Sheet: String, Identifiable, Hashable, CaseIterable {
        case flightTracker, documentVault, packingList, groundTransport, currency
        /// The Siri guide. Its home is a row in More; a routed request shows it here.
        case siriGuide
        /// The Add Trip form, for `jetsetterpro://trip/new`.
        case newTrip
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
        /// Show this wallet pass. Consumed by the Wallet tab.
        case showWalletPass(UUID)
        /// Show the pass for this flight, or the wallet list when there isn't
        /// one. Consumed by the Wallet tab.
        case showBoardingPass(flightNumber: String?, departure: Date?)
        /// Show this flight. Consumed by Home, which has its card.
        case showFlight(String)
    }
    var pendingAction: PendingAction?

    /// Clears `pendingAction` if it equals `action` (so a stale consumer can't
    /// wipe a newer request).
    func consume(_ action: PendingAction) {
        if pendingAction == action { pendingAction = nil }
    }

    // MARK: - Closing modals

    /// Bumped by `dismissPresentedModals()`. Views that present their own
    /// sheets watch it and close them; the router can only close its own.
    private(set) var modalDismissalRequest = 0

    /// When a modal was last asked to close.
    private(set) var lastModalDismissal: Date?

    /// How long a dismissal takes to finish. SwiftUI drops a presentation
    /// requested in the same update as a dismissal, so a screen presenting a
    /// sheet for a routed action waits out `presentationDelay()` first.
    static let dismissalSettleTime: TimeInterval = 0.5

    /// Closes the routed sheet and asks every view to close its own modals.
    func dismissPresentedModals(now: Date = Date()) {
        presentedSheet = nil
        modalDismissalRequest &+= 1
        lastModalDismissal = now
    }

    /// How long to wait before presenting, so a dismissal asked for just now
    /// finishes first. Zero when nothing was dismissed recently.
    func presentationDelay(now: Date = Date()) -> Duration {
        guard let last = lastModalDismissal else { return .zero }
        let remaining = Self.dismissalSettleTime - now.timeIntervalSince(last)
        return remaining > 0 ? .milliseconds(Int((remaining * 1000).rounded(.up))) : .zero
    }

    // MARK: - Navigation

    /// Every place the app can be routed to.
    enum Destination: Hashable, Sendable {
        // Tab roots
        case home, itinerary, wallet, expenses, more
        /// The Siri guide (it lives in More; routed requests present it).
        case assistant
        // Modal feature flows
        case checkIn, disruption, flightTracker, documentVault, packingList, groundTransport, currency
        /// The Add Trip form.
        case newTrip
        /// The next trip, which Home leads with.
        case nextTrip
        /// A flight's card on Home.
        case flight(number: String)
        /// One pass in the wallet.
        case walletPass(id: UUID)
        /// The pass for a flight, matched by number or date, else the Wallet tab.
        case boardingPass(flightNumber: String?, departure: Date?)
    }

    /// Switches tabs and/or presents the matching screen.
    func navigate(to destination: Destination) {
        // A routed sheet left up would hide a tab switch or a Home flow.
        if presentedSheet != nil, Self.sheet(for: destination) == nil {
            presentedSheet = nil
            lastModalDismissal = Date()
        }

        switch destination {
        case .home, .nextTrip: selectedTab = .home
        case .itinerary:       selectedTab = .itinerary
        case .wallet:          selectedTab = .wallet
        case .expenses:        selectedTab = .expenses
        case .more:            selectedTab = .more

        // Modal flows hosted by HomeView: hand it a pending action it consumes
        // once mounted (works on cold launch), rather than posting a notification
        // that has no subscriber yet.
        case .checkIn:
            selectedTab = .home
            pendingAction = .checkIn
        case .disruption:
            selectedTab = .home
            pendingAction = .disruption
        case .flight(let number):
            selectedTab = .home
            pendingAction = .showFlight(number)

        // Passes are shown by the Wallet tab.
        case .walletPass(let id):
            selectedTab = .wallet
            pendingAction = .showWalletPass(id)
        case .boardingPass(let flightNumber, let departure):
            selectedTab = .wallet
            pendingAction = .showBoardingPass(flightNumber: flightNumber, departure: departure)

        case .newTrip:
            // Behind the form, the tab the new trip will appear in.
            selectedTab = .itinerary
            presentedSheet = .newTrip

        // Standalone feature screens — presented by ContentView's sheet host.
        case .assistant, .flightTracker, .documentVault, .packingList, .groundTransport, .currency:
            presentedSheet = Self.sheet(for: destination)
        }
    }

    /// The routed sheet a destination presents, if it's one of those.
    static func sheet(for destination: Destination) -> Sheet? {
        switch destination {
        case .assistant:       return .siriGuide
        case .flightTracker:   return .flightTracker
        case .documentVault:   return .documentVault
        case .packingList:     return .packingList
        case .groundTransport: return .groundTransport
        case .currency:        return .currency
        case .newTrip:         return .newTrip
        default:               return nil
        }
    }

    // MARK: - Outside entry points

    /// Navigation asked for from outside the current screen: close whatever is
    /// presented, then go.
    func open(_ destination: Destination) {
        dismissPresentedModals()
        navigate(to: destination)
    }

    /// Handles a `jetsetterpro://` URL. Returns false for any other URL (the
    /// expense providers' OAuth callbacks, for one) so the caller can ignore it.
    @discardableResult
    func open(url: URL) -> Bool {
        guard let link = JetSetterDeepLink(url: url) else { return false }
        open(Self.destination(for: link))
        return true
    }

    /// Where a deep link goes. A flight segment that the app's flight-number
    /// parser doesn't recognise lands on the next trip instead of nowhere.
    static func destination(for link: JetSetterDeepLink) -> Destination {
        switch link {
        case .nextTrip:           return .nextTrip
        case .newTrip:            return .newTrip
        // No single-trip screen is routable yet; the Itinerary tab lists it.
        case .trip:               return .itinerary
        case .wallet:             return .wallet
        case .walletPass(let id): return .walletPass(id: id)
        case .flight(let raw):
            guard let number = TravelStore.extractFlightNumber(from: raw.uppercased()) else { return .nextTrip }
            return .flight(number: number)
        }
    }

    /// Applies a notification response's in-app part. Opening a ride app,
    /// snoozing and Messages happen outside the app and stay with
    /// `NotificationManager`; they are no-ops here.
    func handle(_ route: NotificationRoute) {
        switch route {
        case .deepLink(let link):
            open(Self.destination(for: link))
        case .checkIn:
            open(.checkIn)
        case .disruption:
            open(.disruption)
        case .expenses:
            open(.expenses)
        case .boardingPass(let flightNumber, let departure):
            open(.boardingPass(flightNumber: flightNumber, departure: departure))
        case .ride, .snooze, .lovedOnes, .none:
            break
        }
    }
}
