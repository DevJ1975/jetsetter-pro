// File: Core/Services/IRIS/IRISActionTools.swift
//
// Agentic tools that let IRIS *act* on the app rather than only describe it.
// These complement the read-only tools in IRISTools.swift.
//
//   • OpenScreenTool          — navigation (non-destructive, runs immediately)
//   • TrackFlightTool         — open Flight Tracker + search (non-destructive)
//   • LogExpenseTool          — stage an expense for confirmation
//   • AddTripTool             — stage a trip for confirmation
//   • CheckInTool             — stage a check-in for confirmation
//   • GeneratePackingListTool — stage packing-list generation for confirmation
//
// Writes never commit directly. They build an `IRISPendingAction` and hand it
// to `IRISActionRouter`; the chat surfaces a confirmation card, and the user's
// tap is what runs the `commit` closure. This keeps the model out of the commit
// path, so a misunderstood request can't silently mutate data.

import Foundation
import FoundationModels

// MARK: - Navigation (immediate)

@available(iOS 26.0, *)
struct OpenScreenTool: Tool {
    let name = "openScreen"
    let description = "Open or navigate to a screen in JetSetter Pro for the user. Use when they ask to open, show, go to, or take me to a part of the app."

    @Generable
    struct Arguments {
        @Guide(description: "The screen to open. One of: home, itinerary, iris, expenses, more, checkIn, disruption, flightTracker, documentVault, packingList, groundTransport, currency.")
        var screen: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let destination = OpenScreenTool.resolve(arguments.screen) else {
            return "I couldn't match \"\(arguments.screen)\" to a screen. Try: home, itinerary, expenses, check-in, flight tracker, documents, packing list, ground transport, or currency."
        }
        await MainActor.run {
            IRISActionRouter.shared.navigate(to: destination)
        }
        return "Opening \(destination.displayName)."
    }

    /// Maps free-text screen names (and common synonyms) onto a Destination.
    static func resolve(_ raw: String) -> IRISActionRouter.Destination? {
        let key = raw.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        func has(_ needles: [String]) -> Bool { needles.contains { key.contains($0) } }

        // Order matters: check more specific phrases before generic ones.
        if has(["check in", "checkin", "boarding pass", "board"])          { return .checkIn }
        if has(["disruption", "delay", "rebook", "cancel"])                { return .disruption }
        if has(["flight tracker", "track flight", "flight status", "flights", "flight"]) { return .flightTracker }
        if has(["document", "vault", "passport", "visa doc"])              { return .documentVault }
        if has(["packing", "pack list", "pack"])                           { return .packingList }
        if has(["ground transport", "transport", "ride", "uber", "lyft", "taxi", "rental car", "car"]) { return .groundTransport }
        if has(["currency", "exchange rate", "forex", "fx"])               { return .currency }
        if has(["itinerary", "my trips", "trips", "trip", "schedule"])     { return .itinerary }
        if has(["expense", "spending", "budget", "receipt"])               { return .expenses }
        if has(["iris", "assistant", "chat", "agent"])                     { return .iris }
        if has(["more", "settings", "menu", "options"])                    { return .more }
        if has(["home", "dashboard", "main", "start"])                     { return .home }
        return nil
    }
}

// MARK: - Track Flight (immediate — read-only lookup)

@available(iOS 26.0, *)
struct TrackFlightTool: Tool {
    let name = "trackFlight"
    let description = "Open the Flight Tracker and look up live status for a specific flight number."

    @Generable
    struct Arguments {
        @Guide(description: "Flight number to track, e.g. 'AA100' or 'UA55'.")
        var flightNumber: String
    }

    func call(arguments: Arguments) async throws -> String {
        let number = arguments.flightNumber.trimmingCharacters(in: .whitespaces).uppercased()
        guard !number.isEmpty else { return "Which flight number should I track?" }
        await MainActor.run {
            IRISActionRouter.shared.navigate(to: .flightTracker)
            NotificationCenter.default.post(name: .jetSetterTrackFlight, object: number)
        }
        return "Pulling up live status for \(number)."
    }
}

// MARK: - Log Expense (confirm before commit)

@available(iOS 26.0, *)
struct LogExpenseTool: Tool {
    let name = "logExpense"
    let description = "Prepare a travel expense to log. This does NOT save immediately — the user must confirm. Never tell the user it's saved before they confirm."

    @Generable
    struct Arguments {
        @Guide(description: "Amount of the expense, e.g. 45.20.")
        var amount: Double
        @Guide(description: "Where the money was spent, e.g. 'Hertz' or 'Nobu Restaurant'.")
        var merchant: String
        @Guide(description: "Three-letter currency code. Defaults to USD.")
        var currency: String?
        @Guide(description: "Category: food, transport, accommodation, entertainment, business, shopping, medical, mileage, or other.")
        var category: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let currency = (arguments.currency ?? "USD").uppercased()
        let category = ExpenseCategory(rawValue: (arguments.category ?? "other").lowercased()) ?? .other
        let merchant = arguments.merchant
        let amount = arguments.amount
        let summary = String(format: "Log %@ %.2f at %@ (%@)", currency, amount, merchant, category.displayName)

        await MainActor.run {
            let action = IRISPendingAction(kind: .logExpense, summary: summary) {
                TravelStore.appendExpense(
                    Expense(amount: amount, currency: currency, category: category, merchant: merchant)
                )
                return "Logged \(currency) \(String(format: "%.2f", amount)) at \(merchant)."
            }
            IRISActionRouter.shared.proposeAction(action)
        }
        return "Prepared: \(summary). Ask the user to confirm — it is NOT saved yet."
    }
}

// MARK: - Add Trip (confirm before commit)

@available(iOS 26.0, *)
struct AddTripTool: Tool {
    let name = "addTrip"
    let description = "Prepare a new trip to add to the user's itinerary. This does NOT save immediately — the user must confirm first."

    @Generable
    struct Arguments {
        @Guide(description: "Destination, e.g. 'Tokyo' or 'Paris, France'.")
        var destination: String
        @Guide(description: "Trip start date as yyyy-MM-dd, e.g. 2026-08-15.")
        var startDate: String
        @Guide(description: "Trip end date as yyyy-MM-dd, e.g. 2026-08-21.")
        var endDate: String
        @Guide(description: "Optional trip name. Defaults to 'Trip to <destination>'.")
        var name: String?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let start = Self.parseDate(arguments.startDate),
              let end = Self.parseDate(arguments.endDate) else {
            return "I couldn't read those dates. Please give start and end dates like 2026-08-15."
        }
        guard end >= start else {
            return "The end date is before the start date — could you restate the dates?"
        }
        let destination = arguments.destination
        let name = (arguments.name.map { $0.isEmpty ? nil : $0 } ?? nil) ?? "Trip to \(destination)"
        let df = DateFormatter(); df.dateStyle = .medium
        let summary = "Add \"\(name)\" — \(destination), \(df.string(from: start)) → \(df.string(from: end))"

        await MainActor.run {
            let action = IRISPendingAction(kind: .addTrip, summary: summary) {
                TravelStore.appendTrip(
                    Trip(name: name, destination: destination, startDate: start, endDate: end)
                )
                return "Added \(name) to your itinerary."
            }
            IRISActionRouter.shared.proposeAction(action)
        }
        return "Prepared: \(summary). Ask the user to confirm — it is NOT saved yet."
    }

    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}

// MARK: - Check In (confirm before commit)

@available(iOS 26.0, *)
struct CheckInTool: Tool {
    let name = "checkInForFlight"
    let description = "Mark the user as checked in for their next upcoming flight. The user must confirm before it's recorded."

    @Generable
    struct Arguments {
        @Guide(description: "Optional flight number (e.g. 'AA169'). If omitted, the next upcoming flight is used.")
        var flightNumber: String?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let flight = TravelStore.nextUpcomingFlight() else {
            return "I don't see an upcoming flight to check in for."
        }
        let number = flight.flightNumber
        let departure = flight.departure
        let summary = "Check in for \(number) — \(flight.label)"

        await MainActor.run {
            let action = IRISPendingAction(kind: .checkIn, summary: summary) {
                CheckInStateStore.markCheckedIn(flightNumber: number, departure: departure)
                return "You're checked in for \(number)."
            }
            IRISActionRouter.shared.proposeAction(action)
        }
        return "Prepared check-in for \(number). Ask the user to confirm — it is NOT recorded yet."
    }
}

// MARK: - Generate Packing List (confirm before commit)

@available(iOS 26.0, *)
struct GeneratePackingListTool: Tool {
    let name = "generatePackingList"
    let description = "Generate a smart packing list for the user's active or upcoming trip. The user must confirm before it generates."

    @Generable
    struct Arguments {
        @Guide(description: "Optional trip name to target; defaults to the active or next upcoming trip.")
        var tripName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let wanted = arguments.tripName?.trimmingCharacters(in: .whitespaces).lowercased()
        let trip: Trip? = {
            if let wanted, !wanted.isEmpty {
                return TravelStore.loadTrips().first {
                    $0.name.lowercased().contains(wanted) || $0.destination.lowercased().contains(wanted)
                }
            }
            return TravelStore.activeOrNextTrip()
        }()
        guard let trip else {
            return "Add a trip first and I'll build a packing list for it."
        }
        let tripID = trip.id.uuidString
        let tripName = trip.name
        let destination = trip.destination
        let summary = "Generate a packing list for \(tripName) (\(destination))"

        await MainActor.run {
            let action = IRISPendingAction(kind: .generatePackingList, summary: summary) {
                IRISActionRouter.shared.navigate(to: .packingList)
                NotificationCenter.default.post(name: .jetSetterGeneratePackingList, object: tripID)
                return "Building your packing list for \(destination)…"
            }
            IRISActionRouter.shared.proposeAction(action)
        }
        return "Prepared: \(summary). Ask the user to confirm — it hasn't generated yet."
    }
}

// MARK: - Display names

extension IRISActionRouter.Destination {
    nonisolated var displayName: String {
        switch self {
        case .home:            return "Home"
        case .itinerary:       return "your Itinerary"
        case .iris:            return "IRIS"
        case .expenses:        return "Expenses"
        case .more:            return "More"
        case .checkIn:         return "Check-In"
        case .disruption:      return "the Disruption dashboard"
        case .flightTracker:   return "Flight Tracker"
        case .documentVault:   return "Document Vault"
        case .packingList:     return "your Packing List"
        case .groundTransport: return "Ground Transport"
        case .currency:        return "Currency & Expenses"
        }
    }
}
