// File: Core/Services/IRIS/IRISFlightActionsTool.swift
//
// One consolidated IRIS tool for the live-flight-tracker feature, kept as a
// single tool (with an `action` switch) to respect Apple's 3–5-tools guidance
// rather than adding several narrow tools. It covers two conversational asks:
//
//   • notifyLovedOnes — open a PRE-FILLED Messages composer to a loved one on
//     takeoff/landing (iOS can't send SMS silently; the user taps Send).
//   • luggageStatus   — report where the user's checked bags are, plus the
//     estimated time to the carousel after landing.
//
// Both are non-destructive: notify opens the system composer (user confirms by
// sending); luggage is read-only. So neither stages an IRISPendingAction.

import Foundation
import FoundationModels

@available(iOS 26.0, *)
struct FlightActionsTool: Tool {
    let name = "flightActions"
    let description = "Flight-day helpers. Set action to 'notifyLovedOnes' to text the user's saved loved ones that they're taking off or have landed (opens a pre-filled message the user sends), or 'luggageStatus' to report where their checked bags are and when they'll reach the carousel."

    @Generable
    struct Arguments {
        @Guide(description: "Which helper to run: 'notifyLovedOnes' or 'luggageStatus'.")
        var action: String
        @Guide(description: "For notifyLovedOnes only — the milestone: 'takeoff' or 'landing'. Defaults to 'landing'.")
        var event: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action.lowercased() {
        case "notifylovedones", "notify", "textlovedones", "text":
            return await notifyLovedOnes(eventRaw: arguments.event)
        case "luggagestatus", "luggage", "bag", "bags", "baggage":
            return await luggageStatus()
        default:
            return "Unknown action '\(arguments.action)'. Use 'notifyLovedOnes' or 'luggageStatus'."
        }
    }

    // MARK: - Notify loved ones

    private func notifyLovedOnes(eventRaw: String?) async -> String {
        let event: LovedOnesEvent = (eventRaw?.lowercased() == "takeoff") ? .takeoff : .landing
        return await MainActor.run {
            let contacts = LovedOnesStore.shared.contacts(for: event)
            guard !contacts.isEmpty else {
                return "There are no loved ones saved for \(event.rawValue). Add them in Settings → Travel Contacts first."
            }
            let body = LovedOnesMessenger.message(for: event, flightNumber: nil, destinationCity: nil)
            let names = contacts.map(\.name).joined(separator: ", ")
            guard LovedOnesMessenger.shared.canSend else {
                // Simulator / device without Messages — be honest.
                return "This device can't send texts, so I can't open Messages. On a phone I'd pre-fill: \"\(body)\" to \(names)."
            }
            LovedOnesMessenger.shared.presentComposer(
                recipients: contacts.map(\.phoneNumber),
                body: body
            )
            return "Opening Messages to \(names) with \"\(body)\" — just tap Send."
        }
    }

    // MARK: - Luggage status

    private func luggageStatus() async -> String {
        let bags = loadBags()
        guard !bags.isEmpty else {
            return "I don't see any bags registered yet. Add one in the Luggage tracker."
        }
        let lines = bags.map { bag -> String in
            var line = "• \(bag.nickname): \(bag.status.displayName)"
            if let loc = bag.lastLocation { line += " (\(loc))" }
            if bag.bagTagNumber != nil, isEnRoute(bag.status) {
                let est = BagDeliveryEstimator.estimate(
                    airportIATA: destinationIATA(from: bag.lastLocation) ?? "",
                    hasCheckedBag: true
                )
                line += " — ~\(est.display) to carousel after landing"
            }
            return line
        }
        return lines.joined(separator: "\n")
    }

    private func isEnRoute(_ status: BagStatus) -> Bool {
        switch status {
        case .inTransit, .loading, .onAircraft, .arrived, .onBelt: return true
        default: return false
        }
    }

    private func destinationIATA(from location: String?) -> String? {
        guard let loc = location,
              let range = loc.range(of: "\\b[A-Z]{3}\\b", options: .regularExpression)
        else { return nil }
        return String(loc[range])
    }

    private func loadBags() -> [Bag] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_bags") else { return [] }
        let iso = JSONDecoder(); iso.dateDecodingStrategy = .iso8601
        if let bags = try? iso.decode([Bag].self, from: data) { return bags }
        return (try? JSONDecoder().decode([Bag].self, from: data)) ?? []   // tolerant fallback
    }
}
