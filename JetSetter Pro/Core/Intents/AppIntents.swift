// File: Core/Intents/AppIntents.swift
//
// JetSetter Pro's assistant is Siri. Every action the app can take for a
// traveler is an App Intent here, so it works from Siri, Spotlight, the
// Shortcuts app, the Action button, and Apple Intelligence — with no custom
// chat surface and no cloud model. Read-only intents answer in place; intents
// that write ask for confirmation first; intents that need a screen open the
// app and route there via `AppRouter`.

import AppIntents
import Foundation
import CoreLocation

// MARK: - Enums

enum ExpenseCategoryChoice: String, AppEnum {
    case food, transport, accommodation, entertainment, business, shopping, medical, other

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Expense Category")
    static var caseDisplayRepresentations: [ExpenseCategoryChoice: DisplayRepresentation] = [
        .food: "Food", .transport: "Transport", .accommodation: "Accommodation",
        .entertainment: "Entertainment", .business: "Business", .shopping: "Shopping",
        .medical: "Medical", .other: "Other"
    ]

    var category: ExpenseCategory {
        switch self {
        case .food:          return .food
        case .transport:     return .transport
        case .accommodation: return .accommodation
        case .entertainment: return .entertainment
        case .business:      return .business
        case .shopping:      return .shopping
        case .medical:       return .medical
        case .other:         return .other
        }
    }
}

enum PreferenceCategoryChoice: String, AppEnum {
    case dietary, seating, hotelStyle, airlinePreference, transportation, destinations, activities, general

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Preference Type")
    static var caseDisplayRepresentations: [PreferenceCategoryChoice: DisplayRepresentation] = [
        .dietary: "Dietary", .seating: "Seating", .hotelStyle: "Hotel Style",
        .airlinePreference: "Airline", .transportation: "Transportation",
        .destinations: "Destinations", .activities: "Activities", .general: "General"
    ]

    var category: TravelerPreference.Category {
        switch self {
        case .dietary:           return .dietary
        case .seating:           return .seating
        case .hotelStyle:        return .hotelStyle
        case .airlinePreference: return .airlinePreference
        case .transportation:    return .transportation
        case .destinations:      return .destinations
        case .activities:        return .activities
        case .general:           return .general
        }
    }
}

enum LovedOnesMilestone: String, AppEnum {
    case takeoff, landing
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Milestone")
    static var caseDisplayRepresentations: [LovedOnesMilestone: DisplayRepresentation] = [
        .takeoff: "Taking off", .landing: "Landed"
    ]
    var event: LovedOnesEvent { self == .takeoff ? .takeoff : .landing }
}

enum AppScreen: String, AppEnum {
    case home, itinerary, expenses, flightTracker, documentVault, packingList, groundTransport, currency, disruption

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Screen")
    static var caseDisplayRepresentations: [AppScreen: DisplayRepresentation] = [
        .home: "Home", .itinerary: "Itinerary", .expenses: "Expenses", .flightTracker: "Flight Tracker",
        .documentVault: "Document Vault", .packingList: "Packing List", .groundTransport: "Ground Transport",
        .currency: "Currency", .disruption: "Trip Disruptions"
    ]

    var destination: AppRouter.Destination {
        switch self {
        case .home: return .home
        case .itinerary: return .itinerary
        case .expenses: return .expenses
        case .flightTracker: return .flightTracker
        case .documentVault: return .documentVault
        case .packingList: return .packingList
        case .groundTransport: return .groundTransport
        case .currency: return .currency
        case .disruption: return .disruption
        }
    }
}

// MARK: - Trip entity (Spotlight / Siri can name trips)

struct TripEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trip")
    static var defaultQuery = TripQuery()

    let id: UUID
    let name: String
    let destination: String
    let startDate: Date
    let endDate: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(destination) · \(AppDateFormatters.mediumDate.string(from: startDate))"
        )
    }

    init(_ trip: Trip) {
        id = trip.id
        name = trip.name
        destination = trip.destination
        startDate = trip.startDate
        endDate = trip.endDate
    }
}

struct TripQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TripEntity] {
        TravelStore.loadTrips().filter { identifiers.contains($0.id) }.map(TripEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TripEntity] {
        let needle = string.lowercased()
        return TravelStore.loadTrips()
            .filter { $0.name.lowercased().contains(needle) || $0.destination.lowercased().contains(needle) }
            .map(TripEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [TripEntity] {
        TravelStore.loadTrips()
            .filter { $0.endDate >= Date() }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map(TripEntity.init)
    }
}

// MARK: - Currency codes

/// Accepts "usd", "USD", "dollars", "euros", "yen", "pounds" and returns a real
/// ISO 4217 code, or nil so the intent can ask again instead of storing junk.
nonisolated enum CurrencyCodes {
    private static let words: [String: String] = [
        "dollar": "USD", "dollars": "USD", "us dollars": "USD", "bucks": "USD",
        "euro": "EUR", "euros": "EUR",
        "pound": "GBP", "pounds": "GBP", "quid": "GBP", "sterling": "GBP",
        "yen": "JPY", "yuan": "CNY", "rmb": "CNY", "won": "KRW", "rupee": "INR", "rupees": "INR",
        "peso": "MXN", "pesos": "MXN", "franc": "CHF", "francs": "CHF",
        "canadian dollars": "CAD", "australian dollars": "AUD", "baht": "THB", "dirham": "AED", "dirhams": "AED",
        "real": "BRL", "reais": "BRL", "krona": "SEK", "kroner": "NOK", "zloty": "PLN", "lira": "TRY", "rand": "ZAR"
    ]

    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        if upper.count == 3, Locale.commonISOCurrencyCodes.contains(upper) { return upper }
        return words[trimmed.lowercased()]
    }
}

// MARK: - Next Flight

struct NextFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Flight"
    static var description = IntentDescription("Your next upcoming flight in JetSetter Pro.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = TravelStore.nextUpcomingFlight() else {
            return .result(dialog: "You don't have any upcoming flights in JetSetter Pro.")
        }
        var text = "Your next flight is \(next.flightNumber) on \(AppDateFormatters.mediumDateShortTime.string(from: next.departure))."
        if !next.label.isEmpty, next.label != next.flightNumber { text += " \(next.label)." }
        if CheckInStateStore.isCheckedIn(flightNumber: next.flightNumber, departure: next.departure) {
            text += " You're already checked in."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - Next Trip

struct NextTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Trip"
    static var description = IntentDescription("When your next trip starts.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        guard let trip = TravelStore.loadTrips().filter({ $0.startDate > now }).min(by: { $0.startDate < $1.startDate }) else {
            if let active = TravelStore.activeOrNextTrip() {
                return .result(dialog: IntentDialog(stringLiteral: "You're on your \(active.destination) trip until \(AppDateFormatters.mediumDate.string(from: active.endDate))."))
            }
            return .result(dialog: "You don't have any upcoming trips planned.")
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: trip.startDate)).day ?? 0
        let when = days <= 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days, on \(AppDateFormatters.mediumDate.string(from: trip.startDate))"
        return .result(dialog: IntentDialog(stringLiteral: "Your trip to \(trip.destination) starts \(when)."))
    }
}

// MARK: - Log Expense

struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense"
    static var description = IntentDescription("Add a travel expense. The category is suggested on device when you don't give one.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", description: "The expense amount.")
    var amount: Double

    @Parameter(title: "Merchant", description: "Where the expense was incurred.", default: "Travel expense")
    var merchant: String

    @Parameter(title: "Currency", description: "Three-letter currency code.", default: "USD")
    var currency: String

    @Parameter(title: "Category", description: "Leave empty to let JetSetter Pro suggest one.")
    var category: ExpenseCategoryChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) \(\.$currency) at \(\.$merchant)") {
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { throw $amount.needsValueError("How much was it?") }
        guard let code = CurrencyCodes.normalized(currency) else {
            throw $currency.needsValueError("Which currency? Use a three-letter code like USD or EUR.")
        }
        let resolved: ExpenseCategory
        if let chosen = category?.category {
            resolved = chosen
        } else {
            resolved = await ExpenseCategorizer.shared.suggestCategory(merchant: merchant) ?? .other
        }

        let amountText = amount.formatted(.currency(code: code))
        try await requestConfirmation(
            result: .result(dialog: IntentDialog(stringLiteral: "Log \(amountText) at \(merchant) as \(resolved.displayName)?"))
        )

        TravelStore.appendExpense(Expense(amount: amount, currency: code, category: resolved, merchant: merchant))
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(amountText) at \(merchant) under \(resolved.displayName)."))
    }
}

// MARK: - Convert Currency

struct ConvertCurrencyIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Currency"
    static var description = IntentDescription("Convert an amount between currencies at the latest rates.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "From", description: "Currency code, e.g. EUR", default: "USD") var from: String
    @Parameter(title: "To", description: "Currency code, e.g. JPY", default: "EUR") var to: String

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$amount) \(\.$from) to \(\.$to)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let base = CurrencyCodes.normalized(from) else {
            throw $from.needsValueError("Which currency are you converting from? Use a code like USD.")
        }
        guard let quote = CurrencyCodes.normalized(to) else {
            throw $to.needsValueError("Which currency are you converting to? Use a code like JPY.")
        }
        guard let rates = await ExchangeRateService.shared.rates(for: base), let rate = rates.rates[quote] else {
            return .result(dialog: IntentDialog(stringLiteral: "I couldn't get a rate for \(base) to \(quote) right now."))
        }
        let converted = amount * rate
        let text = "\(amount.formatted(.currency(code: base))) is about \(converted.formatted(.currency(code: quote)))."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - Departure briefing

struct DepartureBriefingIntent: AppIntent {
    static var title: LocalizedStringResource = "When Should I Leave"
    static var description = IntentDescription("The latest leave-by time from the Departure Optimizer.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = TravelStore.nextUpcomingFlight() else {
            return .result(dialog: "You don't have an upcoming flight to plan for.")
        }
        if let briefing = DepartureBriefing.current(for: next.flightNumber) {
            return .result(dialog: IntentDialog(stringLiteral: briefing.summary))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Open the Departure Optimizer in JetSetter Pro on the day of \(next.flightNumber) and I'll work out a leave-by time from live traffic and security waits."))
    }
}

// MARK: - Weather at destination

struct DestinationWeatherIntent: AppIntent {
    static var title: LocalizedStringResource = "Destination Weather"
    static var description = IntentDescription("Current weather at your next trip's destination.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let trip = TravelStore.activeOrNextTrip() else {
            return .result(dialog: "Add a trip first and I'll check the weather there.")
        }
        guard let coordinate = try? await CLGeocoder().geocodeAddressString(trip.destination).first?.location?.coordinate else {
            return .result(dialog: IntentDialog(stringLiteral: "I couldn't place \(trip.destination) on the map."))
        }
        guard let weather = try? await WeatherService.shared.fetch(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
            return .result(dialog: IntentDialog(stringLiteral: "Weather for \(trip.destination) isn't available right now."))
        }
        return .result(dialog: IntentDialog(stringLiteral: "It's \(Int(weather.temperatureFahrenheit.rounded()))°F and \(weather.conditionDescription.lowercased()) in \(trip.destination)."))
    }
}

// MARK: - Check in

struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In"
    static var description = IntentDescription("Opens the airline's check-in for your next flight and saves the pass to your wallet.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = TravelStore.nextUpcomingFlight() else {
            return .result(dialog: "You don't have an upcoming flight to check in for.")
        }
        AppRouter.shared.navigate(to: .checkIn)
        return .result(dialog: IntentDialog(stringLiteral: "Opening check-in for \(next.flightNumber)."))
    }
}

// MARK: - Bag status

struct BagStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Where Are My Bags"
    static var description = IntentDescription("The status of the bags you've registered.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let bags = BagStore.load()
        guard !bags.isEmpty else {
            return .result(dialog: "No bags are registered yet. Add one in Luggage Tracker.")
        }
        let formatter = RelativeDateTimeFormatter()
        let lines = bags.map { bag -> String in
            var line = "\(bag.nickname): \(bag.status.displayName)"
            if let loc = bag.lastLocation, !loc.isEmpty { line += ", last seen \(loc)" }
            if let checked = bag.lastChecked { line += ", updated \(formatter.localizedString(for: checked, relativeTo: Date()))" }
            if bag.hasAirTag { line += ". Find My has its live position" }
            return line
        }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: ". ") + "."))
    }
}

// MARK: - Packing list

struct GeneratePackingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Build Packing List"
    static var description = IntentDescription("Builds a packing list for your next trip on this iPhone from the forecast, your plans and your preferences.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let trip = TravelStore.activeOrNextTrip() else {
            return .result(dialog: "Add a trip first and I'll pack for it.")
        }
        // The packing screen consumes this once it's on screen (cold launch safe).
        AppRouter.shared.pendingAction = .generatePackingList(tripID: trip.id)
        AppRouter.shared.navigate(to: .packingList)
        return .result(dialog: IntentDialog(stringLiteral: "Packing for \(trip.destination) — items appear as they're written."))
    }
}

// MARK: - Remember a preference

struct RememberPreferenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Remember Preference"
    static var description = IntentDescription("Saves a travel preference, like a seat or dietary need, for future trips.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Preference", description: "e.g. aisle seat, vegetarian, boutique hotels")
    var value: String

    @Parameter(title: "Type", default: .general)
    var type: PreferenceCategoryChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Remember \(\.$value) as \(\.$type)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw $value.needsValueError("What should I remember?") }
        TravelerMemory.shared.remember(category: type.category, value: trimmed)
        return .result(dialog: IntentDialog(stringLiteral: "Got it — I'll remember \(trimmed)."))
    }
}

// MARK: - My Travel Style (learned profile)

struct TravelPersonaIntent: AppIntent {
    static var title: LocalizedStringResource = "My Travel Style"
    static var description = IntentDescription("What JetSetter Pro has learned about your travel style, on this iPhone.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard UserPreferences.shared.learningEnabled else {
            return .result(dialog: "Learning is turned off. Turn it on in JetSetter Pro's settings and it'll start noticing your travel style.")
        }
        let store = TravelProfileStore.shared
        if !store.persona.isEmpty {
            return .result(dialog: IntentDialog(stringLiteral: store.persona))
        }
        let summary = store.profile.summaryForPrompt()
        guard !summary.isEmpty else {
            return .result(dialog: "Not enough trips yet to know your style. Take a few and ask again.")
        }
        let spoken = summary
            .components(separatedBy: "\n")
            .dropFirst()
            .map { $0.replacingOccurrences(of: "• ", with: "") }
            .joined(separator: ". ")
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - Text loved ones

struct NotifyLovedOnesIntent: AppIntent {
    static var title: LocalizedStringResource = "Text My Loved Ones"
    static var description = IntentDescription("Opens a pre-filled message to your saved travel contacts. You tap Send.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Milestone", default: .landing)
    var milestone: LovedOnesMilestone

    static var parameterSummary: some ParameterSummary {
        Summary("Text loved ones that I'm \(\.$milestone)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let event = milestone.event
        let contacts = LovedOnesStore.shared.contacts(for: event)
        guard !contacts.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "No travel contacts are saved for \(event.rawValue). Add them in Settings → Travel Contacts."))
        }
        AppRouter.shared.pendingAction = .notifyLovedOnes(event)
        AppRouter.shared.navigate(to: .home)
        let names = contacts.map(\.name).joined(separator: ", ")
        return .result(dialog: IntentDialog(stringLiteral: "Opening a message to \(names) — just tap Send."))
    }
}

// MARK: - Open a screen

struct OpenScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Open JetSetter Pro Screen"
    static var description = IntentDescription("Jump to a screen in JetSetter Pro.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Screen") var screen: AppScreen

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$screen)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigate(to: screen.destination)
        return .result()
    }
}

// MARK: - App Shortcuts (what Siri understands by phrase)

struct JetSetterAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .navy

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
                "Log an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "\(.applicationName) log expense"
            ],
            shortTitle: "Log Expense",
            systemImageName: "dollarsign.circle.fill"
        )
        AppShortcut(
            intent: ConvertCurrencyIntent(),
            phrases: [
                "Convert currency in \(.applicationName)",
                "\(.applicationName) exchange rate"
            ],
            shortTitle: "Convert Currency",
            systemImageName: "arrow.left.arrow.right.circle.fill"
        )
        AppShortcut(
            intent: DepartureBriefingIntent(),
            phrases: [
                "When should I leave for the airport in \(.applicationName)?",
                "\(.applicationName) when should I leave",
                "Leave-by time in \(.applicationName)"
            ],
            shortTitle: "When to Leave",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: DestinationWeatherIntent(),
            phrases: [
                "What's the weather at my destination in \(.applicationName)?",
                "\(.applicationName) destination weather"
            ],
            shortTitle: "Destination Weather",
            systemImageName: "cloud.sun.fill"
        )
        AppShortcut(
            intent: CheckInIntent(),
            phrases: [
                "Check in for my flight in \(.applicationName)",
                "\(.applicationName) check in"
            ],
            shortTitle: "Check In",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: BagStatusIntent(),
            phrases: [
                "Where are my bags in \(.applicationName)?",
                "\(.applicationName) bag status"
            ],
            shortTitle: "My Bags",
            systemImageName: "suitcase.rolling.fill"
        )
        AppShortcut(
            intent: GeneratePackingListIntent(),
            phrases: [
                "Build my packing list in \(.applicationName)",
                "Pack for my trip in \(.applicationName)",
                "\(.applicationName) packing list"
            ],
            shortTitle: "Packing List",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: TravelPersonaIntent(),
            phrases: [
                "What does \(.applicationName) know about my travel style?",
                "My travel style in \(.applicationName)"
            ],
            shortTitle: "My Travel Style",
            systemImageName: "brain.head.profile"
        )
    }
}
