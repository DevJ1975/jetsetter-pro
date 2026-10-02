// File: JetSetter ProTests/BoardingPassRoutingTests.swift
//
// "Show my boarding pass" has to pick the pass the traveler needs at this
// moment, not just the first one in the wallet. These cover the airport
// moments where a wrong pick sends someone to the wrong line: connections,
// delays, passes scanned from paper (day only, no time), and a flight with no
// pass saved yet. All pure: a fixed clock, no wallet store, no UI.

import Testing
import Foundation
import AppIntents
@testable import JetSetter_Pro

struct BoardingPassRoutingTests {

    private static let hour: TimeInterval = 3_600
    /// A fixed "now" so the tests don't depend on the time of day they run.
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func pass(_ flight: String, departs offset: TimeInterval, scanned: Bool = false) -> WalletItem {
        var raw = ["flight_number": flight]
        if scanned { raw["source"] = "bcbp_scan" }
        return WalletItem(itemType: .boardingPass, title: flight, date: now.addingTimeInterval(offset), rawData: raw)
    }

    // MARK: - Picking the pass

    /// Defect this prevents: on a connection day the first leg's pass stayed
    /// "current" for six hours, so a traveler at the connecting gate was shown
    /// the flight they had already flown.
    @Test func connectionDayShowsTheLegThatHasNotDepartedYet() {
        let first = pass("DL1423", departs: -3 * Self.hour)
        let second = pass("DL2210", departs: 0.75 * Self.hour)
        #expect(BoardingPassRouting.pick(from: [second, first], now: now)?.id == second.id)
    }

    @Test func beforeTheFirstLegTheFirstLegIsShown() {
        let first = pass("DL1423", departs: 1 * Self.hour)
        let second = pass("DL2210", departs: 5 * Self.hour)
        #expect(BoardingPassRouting.pick(from: [second, first], now: now)?.id == first.id)
    }

    @Test func aDelayedFlightKeepsItsPassPastScheduledDeparture() {
        let delayed = pass("UA837", departs: -0.5 * Self.hour)
        let tomorrow = pass("UA838", departs: 26 * Self.hour)
        #expect(BoardingPassRouting.pick(from: [tomorrow, delayed], now: now)?.id == delayed.id)
    }

    @Test func afterTheLastLegTheMostRecentPassIsStillOffered() {
        let landed = pass("B6715", departs: -3 * Self.hour)
        #expect(BoardingPassRouting.pick(from: [landed], now: now)?.id == landed.id)
    }

    /// Defect this prevents: a pass scanned from a paper barcode only carries
    /// the day, saved as local midnight, so a time-based rule treated tonight's
    /// flight as departed by breakfast.
    @Test func aScannedPassWithOnlyADateStaysUsableAllDay() {
        let tonight = pass("F9123", departs: -10 * Self.hour, scanned: true)
        #expect(BoardingPassRouting.pick(from: [tonight], now: now)?.id == tonight.id)
    }

    @Test func yesterdaysPassIsNotOffered() {
        let old = pass("AA100", departs: -8 * Self.hour)
        let olderScan = pass("AA200", departs: -31 * Self.hour, scanned: true)
        #expect(BoardingPassRouting.pick(from: [old, olderScan], now: now) == nil)
    }

    @Test func otherWalletDocumentsAreNeverTreatedAsAPass() {
        let hotel = WalletItem(itemType: .hotelReservation, title: "Ritz-Carlton", date: now)
        #expect(BoardingPassRouting.pick(from: [hotel], now: now) == nil)
    }

    // MARK: - Decision and wording

    @Test func aSavedPassIsOpenedAndNamedByFlight() {
        let next = pass("DL1423", departs: 2 * Self.hour)
        let decision = BoardingPassRouting.decide(walletItems: [next], nextFlightNumber: "DL1423", now: now)
        #expect(decision == .pass(id: next.id, flightNumber: "DL1423"))
        #expect(BoardingPassRouting.dialog(for: decision) == "Here's your DL1423 boarding pass.")
    }

    @Test func withoutAPassSiriSaysWhichFlightNeedsOne() {
        let decision = BoardingPassRouting.decide(walletItems: [], nextFlightNumber: "DL1423", now: now)
        #expect(decision == .noPassForFlight(flightNumber: "DL1423"))
        #expect(BoardingPassRouting.dialog(for: decision).contains("DL1423"))
    }

    /// The unparsed-title token and the wallet's "—" are placeholders, not
    /// flight numbers, and must never be read aloud as one.
    @Test func placeholdersAreNeverSpokenAsFlightNumbers() {
        let unparsed = BoardingPassRouting.decide(walletItems: [], nextFlightNumber: TravelStore.unparsedFlightToken, now: now)
        #expect(unparsed == .noPassForFlight(flightNumber: nil))
        #expect(BoardingPassRouting.dialog(for: unparsed).contains("your next flight"))

        let dashed = pass("—", departs: Self.hour)
        let decision = BoardingPassRouting.decide(walletItems: [dashed], nextFlightNumber: nil, now: now)
        #expect(BoardingPassRouting.dialog(for: decision) == "Here's your boarding pass.")
    }

    @Test func noPassAndNoFlightSaysSoPlainly() {
        let decision = BoardingPassRouting.decide(walletItems: [], nextFlightNumber: nil, now: now)
        #expect(decision == .nothing)
    }

    @Test func deepLinkUsesTheWalletPassRoute() {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        #expect(BoardingPassRouting.deepLink(forPassID: id).absoluteString
                == "jetsetterpro://wallet/pass/6F9619FF-8B86-D011-B42D-00C04FC964FF")
    }

    @Test func showBoardingPassNeedsAnUnlockedPhone() {
        #expect(ShowBoardingPassIntent.authenticationPolicy == .requiresAuthentication)
    }
}
