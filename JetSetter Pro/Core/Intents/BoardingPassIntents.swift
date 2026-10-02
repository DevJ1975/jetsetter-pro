// File: Core/Intents/BoardingPassIntents.swift
//
// The app's half of "Show my boarding pass" (the intent itself is declared in
// Shared/ShowBoardingPassIntent.swift so the Control Center control can open
// the app). This file decides WHICH pass to show and how to get there.
//
// Picking the pass is the part that goes wrong in real travel:
//   • On a connection day the traveler wants the second leg's pass once the
//     first leg has gone. Showing the departed leg at the next gate is the
//     failure that sends people to the wrong line.
//   • A delayed or boarding flight still needs its pass for a while after its
//     scheduled departure, so a pass stays "current" for an hour past it.
//   • A pass scanned from a paper barcode (BCBP) only carries the day, stored
//     as local midnight. `WalletItem.status` marks those completed at 06:00 on
//     the day of an evening flight, so this logic deliberately doesn't use it.
//
// Routing: the pass opens through `jetsetterpro://wallet/pass/<id>`, the deep
// link the router owns. Until that URL scheme is registered the app falls back
// to Home, whose next-flight card is the closest existing screen.

import AppIntents
import Foundation
import UIKit

extension ShowBoardingPassIntent {

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let wallet = await LocalDataService.shared.fetchWalletItems()
        let decision = BoardingPassRouting.decide(
            walletItems: wallet,
            nextFlightNumber: TravelStore.nextUpcomingFlight()?.flightNumber,
            now: Date()
        )
        await BoardingPassRouting.present(decision)
        return .result(dialog: IntentDialog(stringLiteral: BoardingPassRouting.dialog(for: decision)))
    }
}

// MARK: - Choosing and opening the pass

nonisolated enum BoardingPassRouting {

    enum Decision: Equatable {
        /// A saved pass to open.
        case pass(id: UUID, flightNumber: String?)
        /// A flight is coming up but no pass is saved for it yet.
        case noPassForFlight(flightNumber: String?)
        /// No pass and no upcoming flight.
        case nothing
    }

    /// How long after its scheduled departure a timed pass is still the one
    /// the traveler wants (boarding, or a delay at the gate).
    static let departedGrace: TimeInterval = 60 * 60
    /// A pass with only a date (scanned BCBP, stored as local midnight) could
    /// be for any time that day, so it counts as "not gone" all day.
    static let dayOnlyWindow: TimeInterval = 24 * 60 * 60
    /// After this, a timed pass is no longer offered even as a last resort.
    /// Mirrors the 6-hour time-of-use grace `WalletItem.status` applies.
    static let timedRelevance: TimeInterval = 6 * 60 * 60
    /// Day-only passes stay relevant through their day plus the same 6 hours.
    static let dayOnlyRelevance: TimeInterval = 30 * 60 * 60

    static func decide(walletItems: [WalletItem], nextFlightNumber: String?, now: Date) -> Decision {
        if let pass = pick(from: walletItems, now: now) {
            return .pass(id: pass.id, flightNumber: spokenFlightNumber(pass.flightNumber))
        }
        if let nextFlightNumber {
            return .noPassForFlight(flightNumber: spokenFlightNumber(nextFlightNumber))
        }
        return .nothing
    }

    /// The pass the traveler most likely needs right now: the earliest one
    /// that hasn't gone yet; failing that, the most recent one still in use
    /// (in the air, or just landed). Nil when nothing is current.
    static func pick(from items: [WalletItem], now: Date) -> WalletItem? {
        let relevant = items.filter { item in
            item.itemType == .boardingPass
                && now.timeIntervalSince(item.date) <= (isDayOnly(item) ? dayOnlyRelevance : timedRelevance)
        }
        let notGone = relevant.filter { item in
            now.timeIntervalSince(item.date) < (isDayOnly(item) ? dayOnlyWindow : departedGrace)
        }
        if let next = notGone.min(by: { $0.date < $1.date }) { return next }
        return relevant.max(by: { $0.date < $1.date })
    }

    /// True for a pass whose `date` is only a day. The check-in scanner tags
    /// those with `source = bcbp_scan` (`CheckInFlowView.walletItem(from:)`).
    static func isDayOnly(_ item: WalletItem) -> Bool {
        item.rawData["source"] == "bcbp_scan"
    }

    /// The wallet deep link for a pass.
    static func deepLink(forPassID id: UUID) -> URL {
        URL(string: "jetsetterpro://wallet/pass/\(id.uuidString)")!
    }

    static func dialog(for decision: Decision) -> String {
        switch decision {
        case .pass(_, let flight?):
            return "Here's your \(flight) boarding pass."
        case .pass(_, nil):
            return "Here's your boarding pass."
        case .noPassForFlight(let flight?):
            return "There's no boarding pass saved for \(flight) yet. Check in with the airline, then add the pass to Travel Wallet."
        case .noPassForFlight(nil):
            return "There's no boarding pass saved for your next flight yet. Check in with the airline, then add the pass to Travel Wallet."
        case .nothing:
            return "You don't have a boarding pass saved in JetSetter Pro."
        }
    }

    /// Opens the pass through its deep link. When the URL scheme isn't
    /// registered (`open` returns false) or there's no pass, Home is shown.
    @MainActor
    static func present(_ decision: Decision) async {
        if case .pass(let id, _) = decision, await UIApplication.shared.open(deepLink(forPassID: id)) {
            return
        }
        AppRouter.shared.navigate(to: .home)
    }

    /// A flight number fit to say aloud, or nil for placeholders: the wallet's
    /// "—" and TravelStore's unparsed-title token "Flight".
    private static func spokenFlightNumber(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed != "—", trimmed != TravelStore.unparsedFlightToken else { return nil }
        return trimmed
    }
}
