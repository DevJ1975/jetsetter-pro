// File: JetSetter ProTests/NotificationRoutingTests.swift
//
// Notification taps and buttons: which route each response takes, that the
// router holds it until the destination screen consumes it (the cold-launch
// case), how loudly each alert kind may interrupt, and what the announcement
// voice says for each disruption. `UNNotificationResponse` can't be built in a
// test, so the routing is a pure function of the response's plain values.

import Testing
import Foundation
import UserNotifications
@testable import JetSetter_Pro

@MainActor
@Suite(.serialized) struct NotificationRoutingTests {

    private func route(
        category: String = "",
        action: String = UNNotificationDefaultActionIdentifier,
        identifier: String = "test",
        _ userInfo: [AnyHashable: Any] = [:]
    ) -> NotificationRoute {
        NotificationRouting.route(category: category, action: action,
                                  requestIdentifier: identifier, userInfo: userInfo)
    }

    private func withRouter(_ body: (AppRouter) -> Void) {
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
        body(router)
    }

    // MARK: - Buttons

    @Test func viewBoardingPassCarriesTheFlightAndItsDeparture() {
        let departure = Date(timeIntervalSince1970: 1_790_000_000)
        let result = route(category: "FLIGHT_ALERT", action: NotificationRouting.Action.viewBoardingPass, [
            "flightNumber": "DL 1423",
            "departure": departure.timeIntervalSince1970
        ])
        #expect(result == .boardingPass(flightNumber: "DL1423", departure: departure))
    }

    @Test func getARideGoesToTheAirportInThePayload() {
        let result = route(category: "LEAVE_BY_ALERT", action: NotificationRouting.Action.getRide,
                           ["rideAirport": "LAS"])
        #expect(result == .ride(airportIATA: "LAS"))
    }

    @Test func snoozeIsTenMinutes() {
        let result = route(category: "LEAVE_BY_ALERT", action: NotificationRouting.Action.snooze)
        #expect(result == .snooze(minutes: 10))
    }

    @Test func swipingANotificationAwayDoesNothing() {
        #expect(route(category: "DISRUPTION_ALERT", action: UNNotificationDismissActionIdentifier) == .none)
    }

    // MARK: - Plain taps

    @Test func theBackendsDeepLinkWinsOverTheCategory() {
        let result = route(category: "DISRUPTION_ALERT", [
            "deepLink": "jetsetterpro://flight/UA55",
            "flightNumber": "UA55",
            "alertType": "gate_change"
        ])
        #expect(result == .deepLink(.flight("UA55")))
    }

    @Test func anUnreadableDeepLinkFallsBackToTheCategory() {
        #expect(route(category: "DISRUPTION_ALERT", ["deepLink": "https://example.com"]) == .disruption)
    }

    @Test func eachCategoryOpensItsScreen() {
        #expect(route(category: "DISRUPTION_ALERT") == .disruption)
        #expect(route(category: "CHECK_IN_OPEN") == .checkIn)
        #expect(route(category: "EXPENSE_REMINDER") == .expenses)
        #expect(route(category: "FLIGHT_ALERT", ["flightNumber": "DL1423"]) == .deepLink(.flight("DL1423")))
        #expect(route(category: "LEAVE_BY_ALERT") == .deepLink(.nextTrip))
        #expect(route(category: "LOVED_ONES_TAKEOFF", ["recipients": ["+15555550100"], "body": "Off we go"])
                == .lovedOnes(recipients: ["+15555550100"], body: "Off we go"))
    }

    @Test func aBoardingAlertOpensThePass() {
        let result = route(category: "FLIGHT_ALERT", ["flightNumber": "DL1423", "alertType": "boarding"])
        #expect(result == .boardingPass(flightNumber: "DL1423", departure: nil))
    }

    @Test func remindersWithoutACategoryRouteByTheirIdentifier() {
        #expect(route(identifier: "gate_DL1423_C22_1790000000") == .boardingPass(flightNumber: "DL1423", departure: nil))
        #expect(route(identifier: "flight_DL1423_1790000000") == .deepLink(.flight("DL1423")))
        #expect(route(identifier: "checkin_DL1423_1790000000") == .checkIn)
        #expect(route(identifier: "weekly_expense") == .expenses)
        #expect(route(identifier: "trip_eve_1790000000") == .deepLink(.nextTrip))
        #expect(route(identifier: "depart_1790000000.0") == .deepLink(.nextTrip))
        #expect(route(identifier: "something_else") == .none)
    }

    // MARK: - Router (including a cold launch)

    /// Defect: taps were NotificationCenter posts that only a mounted Home view
    /// heard, so a tap that launched the app opened Home and nothing else.
    @Test func aTapThatColdLaunchesTheAppIsHeldUntilItsScreenTakesIt() {
        withRouter { router in
            // Nothing is on screen yet; the delegate applies the route.
            let departure = Date(timeIntervalSince1970: 1_790_000_000)
            let response = route(category: "FLIGHT_ALERT", action: NotificationRouting.Action.viewBoardingPass,
                                 ["flightNumber": "DL1423", "departure": departure.timeIntervalSince1970])
            router.handle(response)

            #expect(router.selectedTab == .wallet)
            let expected = AppRouter.PendingAction.showBoardingPass(flightNumber: "DL1423", departure: departure)
            #expect(router.pendingAction == expected)

            // Home mounts first on launch and must leave the wallet's request alone.
            router.consume(.checkIn)
            #expect(router.pendingAction == expected)

            // The Wallet tab appears and takes it.
            router.consume(expected)
            #expect(router.pendingAction == nil)
        }
    }

    @Test func aTapClosesTheOpenSheetBeforeSwitchingTabs() {
        withRouter { router in
            router.selectedTab = .expenses
            router.presentedSheet = .packingList
            let before = router.modalDismissalRequest
            router.handle(route(category: "DISRUPTION_ALERT"))
            #expect(router.presentedSheet == nil)
            #expect(router.modalDismissalRequest == before &+ 1)
            #expect(router.selectedTab == .home)
            #expect(router.pendingAction == .disruption)
        }
    }

    @Test func aDeepLinkTapReachesItsDestination() {
        withRouter { router in
            router.handle(route(category: "FLIGHT_ALERT", ["deepLink": "jetsetterpro://trip/new"]))
            #expect(router.selectedTab == .itinerary)
            #expect(router.presentedSheet == .newTrip)
        }
    }

    @Test func effectsOutsideTheAppLeaveTheRouterAlone() {
        withRouter { router in
            router.selectedTab = .expenses
            router.handle(.snooze(minutes: 10))
            router.handle(.ride(airportIATA: "LAS"))
            router.handle(.none)
            #expect(router.selectedTab == .expenses)
            #expect(router.pendingAction == nil)
        }
    }

    // MARK: - Categories and snooze

    @Test func theBackendsCategoriesOfferThePassAndARide() throws {
        let categories = NotificationRouting.categories()
        func actions(_ id: String) throws -> [String] {
            try #require(categories.first { $0.identifier == id }).actions.map(\.identifier)
        }
        let passAndRide = [NotificationRouting.Action.viewBoardingPass, NotificationRouting.Action.getRide]
        #expect(try actions("FLIGHT_ALERT") == passAndRide)
        #expect(try actions("DISRUPTION_ALERT") == passAndRide)
        #expect(try actions("LEAVE_BY_ALERT") == passAndRide + [NotificationRouting.Action.snooze])
    }

    @Test func snoozeReschedulesTheSameAlertTenMinutesOut() throws {
        let content = UNMutableNotificationContent()
        content.title = "Flight DL1423 in 2 hours"
        content.categoryIdentifier = "LEAVE_BY_ALERT"
        content.interruptionLevel = .timeSensitive
        let original = UNNotificationRequest(identifier: "flight_DL1423_1790000000", content: content, trigger: nil)

        let snoozed = try #require(NotificationRouting.snoozedRequest(from: original, minutes: 10))
        #expect(snoozed.identifier == "flight_DL1423_1790000000_snoozed")
        #expect(snoozed.content.title == content.title)
        #expect(snoozed.content.categoryIdentifier == "LEAVE_BY_ALERT")
        #expect(snoozed.content.interruptionLevel == .timeSensitive)
        let trigger = try #require(snoozed.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 600)

        // Snoozing again replaces the copy instead of stacking another.
        let again = try #require(NotificationRouting.snoozedRequest(from: snoozed, minutes: 10))
        #expect(again.identifier == snoozed.identifier)
    }

    @Test func aRideGoesToAKnownAirportOnly() throws {
        let url = try #require(NotificationRouting.rideURL(toAirport: "las"))
        #expect(url.absoluteString.contains("m.uber.com"))
        #expect(url.absoluteString.contains("Las%20Vegas"))
        #expect(NotificationRouting.rideURL(toAirport: "XYZ") == nil)
        #expect(NotificationRouting.rideURL(toAirport: nil) == nil)
    }

    // MARK: - Interruption levels

    @Test func eachAlertKindInterruptsAtItsLevel() {
        let expected: [TravelAlertKind: UNNotificationInterruptionLevel] = [
            .gateChange: .timeSensitive,
            .cancellation: .timeSensitive,
            .diversion: .timeSensitive,
            .boarding: .timeSensitive,
            .leaveNow: .timeSensitive,
            .checkInOpen: .timeSensitive,
            .delay: .active,
            .connectionAtRisk: .active,
            .tripReminder: .active,
            .expenseReminder: .active,
            .lovedOnes: .active
        ]
        // Every kind is listed, so a new one can't ship without a decision.
        #expect(Set(expected.keys) == Set(TravelAlertKind.allCases))
        for (kind, level) in expected {
            #expect(kind.interruptionLevel == level, "\(kind)")
        }
    }

    @Test func eachDisruptionMapsToItsAlertKind() {
        #expect(TravelAlertKind(.gateChange) == .gateChange)
        #expect(TravelAlertKind(.cancellation) == .cancellation)
        #expect(TravelAlertKind(.diversion) == .diversion)
        #expect(TravelAlertKind(.majorDelay) == .delay)
        #expect(TravelAlertKind(.missedConnection) == .connectionAtRisk)
    }

    @Test func theBackendsAlertTypeReadsInEitherCase() {
        #expect(TravelAlertKind(alertType: "gate_change") == .gateChange)
        #expect(TravelAlertKind(alertType: "gateChange") == .gateChange)
        #expect(TravelAlertKind(alertType: "major_delay") == .delay)
        #expect(TravelAlertKind(alertType: "BOARDING") == .boarding)
        #expect(TravelAlertKind(alertType: "check_in_open") == .checkInOpen)
        #expect(TravelAlertKind(alertType: "weather") == nil)
        #expect(TravelAlertKind(alertType: nil) == nil)
    }

    // MARK: - Spoken announcements

    private func announce(_ type: DisruptionType, value: String = "x",
                          newDeparture: Date? = nil, zone: TimeZone? = nil) -> Announcement {
        DisruptionAnnouncement.announcement(
            for: DisruptionAlert(type: type, value: value),
            flightNumber: "DL1423", newDeparture: newDeparture, originTimeZone: zone
        )
    }

    @Test func aGateChangeNamesTheNewGate() {
        #expect(announce(.gateChange, value: "C22") == .gateChange(airline: "", flight: "DL1423", gate: "C22"))
    }

    @Test func aDelayNamesTheNewTimeInTheOriginAirportsZone() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let newTime = Date(timeIntervalSince1970: 1_790_000_000)
        let result = announce(.majorDelay, value: "45", newDeparture: newTime, zone: zone)
        #expect(result == .delay(airline: "", flight: "DL1423", newDeparture: newTime, timeZone: zone))
        #expect(AnnouncementScript.clips(for: result)?.contains(AnnouncementScript.newDepartureTimeIs) == true)
    }

    /// Saying the time in the phone's zone would be wrong, so with no airport
    /// zone the voice says only that the flight is delayed.
    @Test func aDelayWithoutTheAirportsZoneSaysNoTime() {
        let result = announce(.majorDelay, value: "45", newDeparture: Date(), zone: nil)
        #expect(AnnouncementScript.clips(for: result) == nil)
        let spoken = AnnouncementScript.resolvedClips(for: result)
        #expect(spoken == AnnouncementScript.genericClips(for: result))
        #expect(spoken.contains(AnnouncementScript.isDelayed))
        #expect(!spoken.contains(AnnouncementScript.newDepartureTimeIs))
    }

    @Test func cancellationDiversionAndConnectionHaveTheirOwnLines() {
        #expect(announce(.cancellation) == .cancelled(airline: "", flight: "DL1423"))
        #expect(announce(.diversion) == .diverted(airline: "", flight: "DL1423"))
        #expect(announce(.missedConnection) == .connectionAtRisk)
    }
}
