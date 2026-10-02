// File: Core/Utilities/BoardingPassMatcher.swift
//
// Finds the wallet boarding pass for an itinerary flight. Home's "Boarding
// pass" button, the Live Activity's button, notification actions and the
// check-in flow all ask the same question, so they share one answer.
//
// Two rules, in order:
//   1. Same flight number within a day of departure. The window matters: a
//      commuter on the same flight every Monday has last week's pass in the
//      wallet too, and that one must never open at the gate. A day either way
//      (rather than an exact instant) is needed because a scanned barcode
//      carries only the date, so its pass sits at midnight.
//   2. With no number match, a pass that carries no flight number of its own
//      (or a flight we couldn't parse) on the same calendar day.
// Flight numbers are compared after `TravelStore.extractFlightNumber`, with
// leading zeros dropped, so "JL006", "JL 6" and "JL6" are the same flight.

import Foundation

nonisolated enum BoardingPassMatcher {

    /// How far a pass's date may sit from the departure for rule 1.
    static let sameFlightWindow: TimeInterval = 24 * 3600

    static func match(
        in items: [WalletItem],
        flightNumber: String?,
        departure: Date?,
        calendar: Calendar = .current
    ) -> WalletItem? {
        let passes = items.filter { $0.itemType == .boardingPass }
        let wanted = flightNumber.flatMap(canonicalFlightNumber)

        func gap(_ pass: WalletItem) -> TimeInterval {
            guard let departure else { return 0 }
            return abs(pass.date.timeIntervalSince(departure))
        }

        // Rule 1: same flight, same trip.
        if let wanted {
            let sameFlight = passes.filter { pass in
                guard pass.flightNumber.flatMap(canonicalFlightNumber) == wanted else { return false }
                return departure == nil || gap(pass) <= sameFlightWindow
            }
            if let best = sameFlight.min(by: { gap($0) < gap($1) }) { return best }
        }

        // Rule 2: a pass with no usable flight number, on the departure's day.
        guard let departure else { return nil }
        let sameDay = passes.filter { pass in
            let passFlight = pass.flightNumber.flatMap(canonicalFlightNumber)
            guard passFlight == nil || wanted == nil else { return false }
            return calendar.isDate(pass.date, inSameDayAs: departure)
        }
        return sameDay.min { gap($0) < gap($1) }
    }

    /// "DL1423" for "dl 1423", "JL6" for "JL006"; nil when there's no flight
    /// number in the text.
    static func canonicalFlightNumber(_ raw: String) -> String? {
        guard let parsed = TravelStore.extractFlightNumber(from: raw.uppercased()) else { return nil }
        let designator = TravelStore.airlineDesignator(from: parsed)
        guard !designator.isEmpty, let number = Int(parsed.dropFirst(designator.count)) else { return nil }
        return designator + String(number)
    }
}
