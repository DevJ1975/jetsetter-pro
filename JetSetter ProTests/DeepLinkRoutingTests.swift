// File: JetSetter ProTests/DeepLinkRoutingTests.swift
//
// `jetsetterpro://` links: what each URL parses to, that the links the widget
// and Live Activity build parse back to themselves, and where the router
// sends each one. The router is a singleton, so every test that drives it
// saves and restores its state.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite(.serialized) struct DeepLinkRoutingTests {

    private func link(_ string: String) throws -> JetSetterDeepLink? {
        JetSetterDeepLink(url: try #require(URL(string: string)))
    }

    /// Runs `body` against the shared router, then puts it back as it was.
    private func withRouter(_ body: (AppRouter) throws -> Void) rethrows {
        let router = AppRouter.shared
        let saved = (router.selectedTab, router.presentedSheet, router.pendingAction)
        defer {
            router.selectedTab = saved.0
            router.presentedSheet = saved.1
            router.pendingAction = saved.2
        }
        router.selectedTab = .home
        router.presentedSheet = nil
        router.pendingAction = nil
        try body(router)
    }

    // MARK: - Parsing

    @Test func eachDocumentedURLParsesToItsLink() throws {
        let id = UUID()
        #expect(try link("jetsetterpro://trip/next") == .nextTrip)
        #expect(try link("jetsetterpro://trip/new") == .newTrip)
        #expect(try link("jetsetterpro://flight/DL1423") == .flight("DL1423"))
        #expect(try link("jetsetterpro://wallet") == .wallet)
        #expect(try link("jetsetterpro://wallet/pass/\(id.uuidString)") == .walletPass(id))
    }

    @Test func schemeHostAndKeywordsAreCaseInsensitive() throws {
        #expect(try link("JetSetterPro://TRIP/Next") == .nextTrip)
        #expect(try link("jetsetterpro://flight/dl1423") == .flight("DL1423"))
        let id = UUID()
        #expect(try link("jetsetterpro://wallet/pass/\(id.uuidString.lowercased())") == .walletPass(id))
    }

    @Test func aHostlessSpellingStillParses() throws {
        #expect(try link("jetsetterpro:///trip/next") == .nextTrip)
    }

    @Test func aSpaceInTheFlightNumberIsDropped() throws {
        #expect(try link("jetsetterpro://flight/DL%201423") == .flight("DL1423"))
    }

    @Test func otherSchemesAndUnknownPathsAreRejected() throws {
        #expect(try link("https://jetsetterpro.app/trip/next") == nil)
        #expect(try link("jetsetter://oauth-callback?code=abc") == nil)
        #expect(try link("jetsetterpro://trip/old") == nil)
        #expect(try link("jetsetterpro://trip") == nil)
        #expect(try link("jetsetterpro://wallet/pass/not-a-uuid") == nil)
        #expect(try link("jetsetterpro://flight") == nil)
        #expect(try link("jetsetterpro://flight/DL-1423") == nil)
        #expect(try link("jetsetterpro://settings") == nil)
    }

    @Test func everyLinkTheWidgetsBuildParsesBackToItself() throws {
        let links: [JetSetterDeepLink] = [.nextTrip, .newTrip, .flight("B6715"), .wallet, .walletPass(UUID())]
        for original in links {
            let url = try #require(original.url)
            #expect(url.scheme == "jetsetterpro")
            #expect(JetSetterDeepLink(url: url) == original)
        }
    }

    // MARK: - URL → router destination

    @Test func eachLinkMapsToItsDestination() {
        let id = UUID()
        #expect(AppRouter.destination(for: .nextTrip) == .nextTrip)
        #expect(AppRouter.destination(for: .newTrip) == .newTrip)
        #expect(AppRouter.destination(for: .wallet) == .wallet)
        #expect(AppRouter.destination(for: .walletPass(id)) == .walletPass(id: id))
        #expect(AppRouter.destination(for: .flight("DL1423")) == .flight(number: "DL1423"))
        #expect(AppRouter.destination(for: .flight("B6715")) == .flight(number: "B6715"))
    }

    /// A flight segment that isn't a flight number lands on the next trip
    /// rather than nowhere.
    @Test func aFlightSegmentTheParserRejectsOpensTheNextTrip() {
        #expect(AppRouter.destination(for: .flight("HELLO")) == .nextTrip)
    }

    @Test func tripNextOpensHome() throws {
        try withRouter { router in
            router.selectedTab = .expenses
            let url = try #require(URL(string: "jetsetterpro://trip/next"))
            #expect(router.open(url: url))
            #expect(router.selectedTab == .home)
            #expect(router.presentedSheet == nil)
        }
    }

    @Test func tripNewOpensTheAddTripFormOverTheItinerary() throws {
        try withRouter { router in
            router.open(url: try #require(URL(string: "jetsetterpro://trip/new")))
            #expect(router.selectedTab == .itinerary)
            #expect(router.presentedSheet == .newTrip)
        }
    }

    @Test func aFlightLinkHandsHomeTheFlight() throws {
        try withRouter { router in
            router.selectedTab = .more
            router.open(url: try #require(URL(string: "jetsetterpro://flight/DL1423")))
            #expect(router.selectedTab == .home)
            #expect(router.pendingAction == .showFlight("DL1423"))
        }
    }

    @Test func aPassLinkOpensTheWalletTabWithThatPass() throws {
        try withRouter { router in
            let id = UUID()
            router.open(url: try #require(URL(string: "jetsetterpro://wallet/pass/\(id.uuidString)")))
            #expect(router.selectedTab == .wallet)
            #expect(router.pendingAction == .showWalletPass(id))
        }
    }

    /// Defect: the router never cleared `presentedSheet`, so a link opened
    /// while a routed sheet was up switched tabs underneath it.
    @Test func openingALinkClosesWhateverIsPresented() throws {
        try withRouter { router in
            router.presentedSheet = .currency
            let before = router.modalDismissalRequest
            router.open(url: try #require(URL(string: "jetsetterpro://wallet")))
            #expect(router.presentedSheet == nil)
            #expect(router.modalDismissalRequest == before &+ 1)
            #expect(router.selectedTab == .wallet)
        }
    }

    @Test func aURLForAnotherSchemeChangesNothing() throws {
        try withRouter { router in
            router.selectedTab = .expenses
            router.presentedSheet = .currency
            let handled = router.open(url: try #require(URL(string: "jetsetter://oauth-callback")))
            #expect(!handled)
            #expect(router.selectedTab == .expenses)
            #expect(router.presentedSheet == .currency)
        }
    }

    // MARK: - Destinations added for the Wallet tab

    @Test func theBoardingPassDestinationAsksTheWalletTabForThatFlight() {
        withRouter { router in
            let departure = Date(timeIntervalSince1970: 1_790_000_000)
            router.navigate(to: .boardingPass(flightNumber: "DL1423", departure: departure))
            #expect(router.selectedTab == .wallet)
            #expect(router.pendingAction == .showBoardingPass(flightNumber: "DL1423", departure: departure))
        }
    }

    @Test func theSiriGuideIsPresentedAsASheetNowThatItHasNoTab() {
        withRouter { router in
            router.navigate(to: .assistant)
            #expect(router.presentedSheet == .siriGuide)
        }
    }

    @Test func aTabSwitchClosesARoutedSheetSoItIsVisible() {
        withRouter { router in
            router.presentedSheet = .documentVault
            router.navigate(to: .expenses)
            #expect(router.presentedSheet == nil)
            #expect(router.selectedTab == .expenses)
        }
    }

    @Test func aPresentationWaitsOutARecentDismissalOnly() {
        withRouter { router in
            let now = Date()
            router.dismissPresentedModals(now: now)
            #expect(router.presentationDelay(now: now.addingTimeInterval(0.1)) > .zero)
            #expect(router.presentationDelay(now: now.addingTimeInterval(1)) == .zero)
        }
    }
}
