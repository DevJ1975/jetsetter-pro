// File: Core/Intents/AppIntents.swift
//
// App Intents that expose JetSetter to Siri, Spotlight, Shortcuts, and the
// Action Button. Three read/write intents:
//   • NextFlightIntent   — speaks the user's next flight info
//   • NextTripIntent     — speaks the user's next trip start date
//   • LogExpenseIntent   — adds a travel expense from a quick voice command

import AppIntents
import Foundation

// MARK: - Next Flight

struct NextFlightIntent: AppIntent {

    static var title: LocalizedStringResource = "Next Flight"
    static var description = IntentDescription(
        "Look up your next upcoming flight in JetSetter Pro."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = TripsLookup.nextFlight() else {
            return .result(dialog: IntentDialog("You don't have any upcoming flights in JetSetter."))
        }

        var components: [String] = [
            "Your next flight is \(context.flightNumber) on \(AppDateFormatters.mediumDateShortTime.string(from: context.departure))."
        ]
        if let route = context.route {
            components.append("Route: \(route).")
        }
        if let gate = context.gate {
            components.append("Gate \(gate).")
        }

        return .result(dialog: IntentDialog(stringLiteral: components.joined(separator: " ")))
    }
}

// MARK: - Next Trip

struct NextTripIntent: AppIntent {

    static var title: LocalizedStringResource = "Next Trip"
    static var description = IntentDescription(
        "Look up when your next trip starts."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let trip = TripsLookup.nextTrip() else {
            return .result(dialog: IntentDialog("You don't have any upcoming trips planned."))
        }

        let days = Calendar.current.dateComponents([.day], from: Date(), to: trip.startDate).day ?? 0
        let when: String
        if days <= 0 {
            when = "today"
        } else if days == 1 {
            when = "tomorrow"
        } else {
            when = "in \(days) days, on \(AppDateFormatters.mediumDate.string(from: trip.startDate))"
        }

        return .result(dialog: IntentDialog(stringLiteral: "Your trip to \(trip.destination) starts \(when)."))
    }
}

// MARK: - Log Expense

struct LogExpenseIntent: AppIntent {

    static var title: LocalizedStringResource = "Log Expense"
    static var description = IntentDescription(
        "Add a travel expense to JetSetter."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", description: "The expense amount.")
    var amount: Double

    @Parameter(title: "Merchant", description: "Where the expense was incurred.", default: "Travel expense")
    var merchant: String

    @Parameter(title: "Currency", description: "Three-letter currency code.", default: "USD")
    var currency: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) \(\.$currency) at \(\.$merchant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let expense = Expense(
            amount: amount,
            currency: currency.uppercased(),
            category: .other,
            merchant: merchant
        )

        TravelStore.appendExpense(expense)

        return .result(
            dialog: IntentDialog(
                stringLiteral: "Logged \(currency.uppercased()) \(String(format: "%.2f", amount)) at \(merchant)."
            )
        )
    }
}

// MARK: - My Travel Style (IRIS learned profile)

struct TravelPersonaIntent: AppIntent {

    static var title: LocalizedStringResource = "My Travel Style"
    static var description = IntentDescription(
        "Hear what IRIS has learned about your travel style."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard UserPreferences.shared.learningEnabled else {
            return .result(dialog: IntentDialog(
                "IRIS learning is turned off. Turn it on in Settings and I'll start learning your travel style."
            ))
        }

        let store = TravelProfileStore.shared
        if !store.persona.isEmpty {
            return .result(dialog: IntentDialog(stringLiteral: store.persona))
        }

        let summary = store.profile.summaryForPrompt()
        guard !summary.isEmpty else {
            return .result(dialog: IntentDialog(
                "I haven't learned enough about your travel style yet. Take a few trips and I'll get to know you."
            ))
        }
        // Drop the leading explanatory header for a cleaner spoken reply.
        let spoken = summary
            .components(separatedBy: "\n")
            .dropFirst()
            .map { $0.replacingOccurrences(of: "• ", with: "") }
            .joined(separator: ". ")
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - App Shortcuts

struct JetSetterAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextFlightIntent(),
            phrases: [
                "What's my next flight in \(.applicationName)?",
                "My next flight in \(.applicationName)",
                "\(.applicationName) next flight"
            ],
            shortTitle: "Next Flight",
            systemImageName: "airplane.departure"
        )
        AppShortcut(
            intent: NextTripIntent(),
            phrases: [
                "When does my trip start in \(.applicationName)?",
                "\(.applicationName) next trip",
                "My next trip in \(.applicationName)"
            ],
            shortTitle: "Next Trip",
            systemImageName: "suitcase.fill"
        )
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log expense in \(.applicationName)",
                "Add expense to \(.applicationName)",
                "\(.applicationName) log expense"
            ],
            shortTitle: "Log Expense",
            systemImageName: "dollarsign.circle.fill"
        )
        AppShortcut(
            intent: TravelPersonaIntent(),
            phrases: [
                "What does \(.applicationName) know about my travel style?",
                "My travel style in \(.applicationName)",
                "\(.applicationName) travel profile"
            ],
            shortTitle: "My Travel Style",
            systemImageName: "brain.head.profile"
        )
    }
}

// MARK: - Trips Lookup helper

private enum TripsLookup {

    struct FlightContext {
        let flightNumber: String
        let route: String?
        let gate: String?
        let departure: Date
    }

    static func nextFlight() -> FlightContext? {
        let trips = loadTrips()
        let now = Date()
        let candidates = trips.flatMap { trip in
            trip.items
                .filter { $0.type == .flight && $0.startDate > now }
                .map { (item: $0, trip: trip) }
        }
        guard let next = candidates.min(by: { $0.item.startDate < $1.item.startDate }) else {
            return nil
        }
        return FlightContext(
            flightNumber: extractFlightNumber(from: next.item.title) ?? next.item.title,
            route: next.item.location,
            gate: extractGate(from: next.item.notes),
            departure: next.item.startDate
        )
    }

    static func nextTrip() -> Trip? {
        let trips = loadTrips()
        let now = Date()
        return trips
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private static func loadTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return [] }
        return (try? JSONCoding.iso8601Decoder.decode([Trip].self, from: data)) ?? []
    }

    private static func extractFlightNumber(from title: String) -> String? {
        let normalized = title.replacingOccurrences(
            of: #"([A-Z]{2,3})\s+(\d)"#,
            with: "$1$2",
            options: .regularExpression
        )
        guard let range = normalized.range(of: #"\b[A-Z]{2,3}\d{1,4}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(normalized[range])
    }

    private static func extractGate(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: #"Gate\s+([A-Z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return String(notes[range]).replacingOccurrences(of: "Gate ", with: "")
    }
}

// Expense persistence now lives in the shared `TravelStore`
// (Core/Services/TravelStore.swift), used by both App Intents and IRIS tools.
