// File: Core/Services/DemoSeeder.swift
//
// Augments MockDataService's seed data so every demo screen has something to
// show. Seeds wallet items, loyalty accounts, IRIS preferences, currency
// expenses, ID state, and disruption events. Idempotent — guards on a key in
// UserDefaults so it runs once per install, and resettable.

import Foundation

enum DemoSeeder {

    private static let populatedKey = "jetsetter_demo_seeder_v2"

    // Local fallback keys (the ViewModels that read these have UserDefaults
    // fallbacks added so they don't need a Firebase sign-in to display data).
    static let walletItemsKey = "jetsetter_wallet_items"
    static let loyaltyAccountsKey = "jetsetter_loyalty_accounts"
    static let disruptionEventsLocalKey = "jetsetter_disruption_events_local"
    static let idStateKey = "jetsetter_id_state"

    /// Seeds the demo augmentation data. Safe to call repeatedly — no-ops if
    /// already populated. Called from MockDataService.prePopulateIfNeeded().
    static func seedAll() {
        guard MockDataService.isEnabled else { return }
        guard !UserDefaults.standard.bool(forKey: populatedKey) else { return }

        let trips = loadSeededTrips()
        let atlantaTrip = trips.first { $0.name.contains("Atlanta") }
        let tokyoTrip   = trips.first { $0.name.contains("Tokyo") }

        seedWalletItems(atlantaTrip: atlantaTrip, tokyoTrip: tokyoTrip)
        seedLoyaltyAccounts()
        seedIRISMemory()
        if let atlantaTrip = atlantaTrip {
            seedDisruptionEvents(tripID: atlantaTrip.id)
        }
        if let tokyoTrip = tokyoTrip {
            seedCurrencyExpenses(tripID: tokyoTrip.id)
        }
        seedIdentityState()

        UserDefaults.standard.set(true, forKey: populatedKey)
    }

    /// Resets the demo augmentation. Called by the hidden version-tap gesture
    /// in SettingsView.
    static func reset() {
        let keys = [
            populatedKey,
            walletItemsKey,
            loyaltyAccountsKey,
            disruptionEventsLocalKey,
            idStateKey,
            "iris_memory",
            "iris_dismissed_suggestions",
            "jetsetter_checked_in_flights",
            MockDataService.populatedKey
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Wipe per-trip currency expenses too
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("jetsetter_currency_expenses_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Wallet items

    private static func seedWalletItems(atlantaTrip: Trip?, tokyoTrip: Trip?) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let cal = Calendar.current

        // Fixed persona dates (Atlanta Board Meeting, Jul 14–17 2026).
        func atl(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = 7; c.day = day; c.hour = hour; c.minute = minute
            return cal.date(from: c) ?? Date()
        }

        // Wallet passes match IOS_PARITY_NOTES.md §7.1 exactly.
        let items: [WalletItem] = [
            // Boarding pass — DL 1423 First 3A Zone 1
            WalletItem(
                tripId: atlantaTrip?.id,
                itemType: .boardingPass,
                title: "DL 1423 · LAS → ATL",
                confirmationNumber: "RC-8842193",
                date: atl(14, hour: 7),
                rawData: [
                    "airline": "Delta Air Lines",
                    "flight_number": "DL1423",
                    "iata_code": "DL",
                    "departure_airport": "LAS",
                    "arrival_airport": "ATL",
                    "seat_number": "3A",
                    "cabin": "First",
                    "boarding_zone": "Zone 1",
                    "gate": "C22",
                    "terminal": "1"
                ]
            ),
            // The Ritz-Carlton, Atlanta
            WalletItem(
                tripId: atlantaTrip?.id,
                itemType: .hotelReservation,
                title: "The Ritz-Carlton, Atlanta",
                confirmationNumber: "RC-8842193",
                date: atl(14, hour: 16),
                rawData: [
                    "hotel_address": "181 Peachtree St NE, Atlanta, GA",
                    "check_in_date": isoString(atl(14, hour: 16)),
                    "check_out_date": isoString(atl(17, hour: 11)),
                    "end_date": isoString(atl(17, hour: 11))
                ]
            ),
            // Hertz — Tesla Model 3
            WalletItem(
                tripId: atlantaTrip?.id,
                itemType: .carRental,
                title: "Hertz — ATL pickup",
                confirmationNumber: "HZ-4471-ATL",
                date: atl(14, hour: 15),
                rawData: [
                    "rental_company": "Hertz",
                    "pickup_location": "ATL Airport — Rental Center",
                    "vehicle_class": "Tesla Model 3",
                    "end_date": isoString(atl(17, hour: 12))
                ]
            ),
            // Q3 Leadership Summit ticket
            WalletItem(
                tripId: atlantaTrip?.id,
                itemType: .eventTicket,
                title: "Q3 Leadership Summit",
                confirmationNumber: "QLS-2026-0714",
                date: atl(15, hour: 9),
                rawData: [
                    "venue": "Atlanta HQ — Executive Boardroom",
                    "event_location": "181 Peachtree St NE, Atlanta, GA"
                ]
            ),
            // AIG Travel Guard insurance
            WalletItem(
                itemType: .travelInsurance,
                title: "AIG Travel Guard",
                confirmationNumber: "TG-9128340",
                date: atl(14),
                rawData: [
                    "provider": "AIG Travel Guard",
                    "policy_number": "TG-9128340-IK",
                    "coverage_type": "Deluxe — Single Trip"
                ]
            )
        ]

        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: walletItemsKey)
        }
    }

    // MARK: - Loyalty accounts

    private static func seedLoyaltyAccounts() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let cal = Calendar.current
        let nowPlus = { (months: Int) in cal.date(byAdding: .month, value: months, to: Date()) }
        let nowPlusDays = { (days: Int) in cal.date(byAdding: .day, value: days, to: Date()) }

        let accounts: [LoyaltyAccount] = [
            LoyaltyAccount(
                programID: "AA",
                memberNumber: "AAdv-7XK29Q1",
                memberSince: cal.date(byAdding: .year, value: -8, to: Date()),
                balance: 247_830,
                tier: "Platinum Pro",
                tierExpiration: nowPlus(14)
            ),
            LoyaltyAccount(
                programID: "MARRIOTT",
                memberNumber: "Bonvoy-918274632",
                memberSince: cal.date(byAdding: .year, value: -5, to: Date()),
                balance: 184_200,
                tier: "Titanium Elite",
                // Tier-at-risk: expires in 4 days. Drives IRIS tierAtRisk trigger.
                tierExpiration: nowPlusDays(4)
            ),
            LoyaltyAccount(
                programID: "HILTON",
                memberNumber: "Honors-554820194",
                memberSince: cal.date(byAdding: .year, value: -3, to: Date()),
                balance: 92_400,
                tier: "Diamond",
                tierExpiration: nowPlus(8)
            ),
            LoyaltyAccount(
                programID: "HERTZ_GR",
                memberNumber: "Hertz-1928374",
                memberSince: cal.date(byAdding: .year, value: -4, to: Date()),
                balance: 0,
                tier: "President's Circle",
                tierExpiration: nowPlus(11),
                notes: "18 rentals YTD"
            ),
            LoyaltyAccount(
                programID: "EK",
                memberNumber: "Skywards-7651928",
                memberSince: cal.date(byAdding: .year, value: -6, to: Date()),
                balance: 88_500,
                tier: "Gold",
                tierExpiration: nowPlus(7)
            )
        ]

        if let data = try? encoder.encode(accounts) {
            UserDefaults.standard.set(data, forKey: loyaltyAccountsKey)
        }
    }

    // MARK: - IRIS memory

    private static func seedIRISMemory() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let prefs: [IRISPreference] = [
            IRISPreference(category: .dietary,
                           value: "Vegetarian, no dairy",
                           confidence: 0.95),
            IRISPreference(category: .seating,
                           value: "Aisle seat near the front (rows 3–6)",
                           confidence: 0.85),
            IRISPreference(category: .hotelStyle,
                           value: "Boutique luxury, city views preferred",
                           confidence: 0.9),
            IRISPreference(category: .airlinePreference,
                           value: "American AAdvantage; Emirates for international",
                           confidence: 0.8),
            IRISPreference(category: .general,
                           value: "Avoids red-eye flights when possible",
                           confidence: 0.75)
        ]
        if let data = try? encoder.encode(prefs) {
            UserDefaults.standard.set(data, forKey: "iris_memory")
        }
    }

    // MARK: - Currency expenses (Tokyo trip)

    private static func seedCurrencyExpenses(tripID: UUID) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let cal = Calendar.current
        let now = Date()
        let daysAgo: (Int) -> Date = { cal.date(byAdding: .day, value: -$0, to: now) ?? now }

        let expenses: [CurrencyExpense] = [
            CurrencyExpense(id: UUID(), tripId: tripID,
                            amount: 4_800, currency: "JPY",
                            convertedAmount: 32.45, homeCurrency: "USD",
                            category: .food, description: "Sushi lunch — Tsukiji",
                            date: daysAgo(1)),
            CurrencyExpense(id: UUID(), tripId: tripID,
                            amount: 65_000, currency: "JPY",
                            convertedAmount: 439.20, homeCurrency: "USD",
                            category: .food, description: "Sukiyabashi Jiro omakase",
                            date: daysAgo(2)),
            CurrencyExpense(id: UUID(), tripId: tripID,
                            amount: 3_500, currency: "JPY",
                            convertedAmount: 23.65, homeCurrency: "USD",
                            category: .transport, description: "Suica card top-up",
                            date: daysAgo(3)),
            CurrencyExpense(id: UUID(), tripId: tripID,
                            amount: 12_000, currency: "JPY",
                            convertedAmount: 81.10, homeCurrency: "USD",
                            category: .shopping, description: "Isetan — gifts for clients",
                            date: daysAgo(2)),
            CurrencyExpense(id: UUID(), tripId: tripID,
                            amount: 2_200, currency: "JPY",
                            convertedAmount: 14.86, homeCurrency: "USD",
                            category: .activities, description: "TeamLab Planets admission",
                            date: daysAgo(4)),
            CurrencyExpense(id: UUID(), tripId: tripID,
                            amount: 8_400, currency: "JPY",
                            convertedAmount: 56.78, homeCurrency: "USD",
                            category: .food, description: "Hotel bar — evening cocktails",
                            date: daysAgo(0))
        ]

        let key = "jetsetter_currency_expenses_\(tripID.uuidString)"
        if let data = try? encoder.encode(expenses) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Disruption events

    private static func seedDisruptionEvents(tripID: UUID) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let cal = Calendar.current
        let now = Date()
        // DL 1423 departure anchor — Jul 14 2026, 7:00 AM (matches the wallet pass).
        func atl(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = 7; c.day = day; c.hour = hour; c.minute = minute
            return cal.date(from: c) ?? now
        }
        let dl1423Departure = atl(14, hour: 7)

        // ===========================================================
        // 1) LEAD ACTIVE — DL 1423 weather hold at ATL: 7:00 → 8:35 AM
        //    (95-min delay). Alternatives match IOS_PARITY_NOTES.md §7.1.
        // ===========================================================
        let weatherHold = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .majorDelay,
            originalFlight: FlightSnapshot(
                flightNumber: "DL1423",
                airline: "Delta Air Lines",
                origin: "LAS",
                destination: "ATL",
                scheduledDeparture: dl1423Departure,
                originalGate: "C22",
                status: "Weather hold at ATL — departure pushed 7:00 → 8:35 AM",
                delayMinutes: 95
            ),
            alternatives: [
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "AA 218",
                    airline: "American Airlines",
                    origin: "LAS",
                    destination: "ATL",
                    departure: atl(14, hour: 9),
                    arrival: atl(14, hour: 15, minute: 25),
                    durationMinutes: 205,
                    price: 412,
                    currency: "USD",
                    availableSeats: 5,
                    cabinClass: "First",
                    bookingToken: "AA218-DEMO-001"
                ),
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "DL 2207",
                    airline: "Delta Air Lines",
                    origin: "LAS",
                    destination: "ATL",
                    departure: atl(14, hour: 10, minute: 30),
                    arrival: atl(14, hour: 16, minute: 58),
                    durationMinutes: 208,
                    price: 289,
                    currency: "USD",
                    availableSeats: 9,
                    cabinClass: "Comfort+",
                    bookingToken: "DL2207-DEMO-002"
                ),
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "WN 1190",
                    airline: "Southwest Airlines",
                    origin: "LAS",
                    destination: "ATL",
                    departure: atl(14, hour: 12),
                    arrival: atl(14, hour: 18, minute: 40),
                    durationMinutes: 220,
                    price: 198,
                    currency: "USD",
                    availableSeats: 14,
                    cabinClass: "Main",
                    bookingToken: "WN1190-DEMO-003"
                )
            ],
            responseActions: ResponseActions(
                alternativesFound: true,
                rebookingChecked: true,
                rebookingEligible: true,
                hotelNotified: true,
                uberRerouteReady: true,
                insuranceSurfaced: true
            ),
            resolved: false,
            rebookingUrl: "https://www.delta.com/rebook",
            hotelContact: "+1-404-659-0400",
            uberDeepLink: "uber://?action=setPickup&pickup=my_location",
            insuranceDocumentId: UUID(),
            createdAt: cal.date(byAdding: .minute, value: -20, to: now) ?? now
        )

        // ===========================================================
        // 2) SECONDARY ACTIVE — DL 1423 gate change (created 45m ago)
        // ===========================================================
        let gateChange = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .gateChange,
            originalFlight: FlightSnapshot(
                flightNumber: "DL1423",
                airline: "Delta Air Lines",
                origin: "LAS",
                destination: "ATL",
                scheduledDeparture: dl1423Departure,
                originalGate: "C22",
                status: "Gate C22 → C31 · 6-min walk within Concourse C",
                delayMinutes: nil
            ),
            alternatives: [],
            responseActions: ResponseActions(
                alternativesFound: false,
                rebookingChecked: false,
                hotelNotified: false,
                uberRerouteReady: true,
                insuranceSurfaced: false
            ),
            resolved: false,
            rebookingUrl: nil,
            hotelContact: nil,
            uberDeepLink: "uber://?action=setPickup&pickup=my_location&dropoff[formatted_address]=Harry%20Reid%20International%20Gate%20C31",
            insuranceDocumentId: nil,
            createdAt: cal.date(byAdding: .minute, value: -45, to: now) ?? now
        )

        // ===========================================================
        // 3) RESOLVED — prior Atlanta trip crew-rest delay (last quarter)
        // ===========================================================
        let resolvedPast = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .majorDelay,
            originalFlight: FlightSnapshot(
                flightNumber: "DL 2456",
                airline: "Delta Air Lines",
                origin: "LAS",
                destination: "ATL",
                scheduledDeparture: dl1423Departure.addingTimeInterval(-90 * 86_400),
                originalGate: "C18",
                status: "Crew-rest delay — held 40 min, departed on rebooked slot",
                delayMinutes: 40
            ),
            alternatives: [],
            responseActions: ResponseActions(
                alternativesFound: true,
                rebookingChecked: true,
                hotelNotified: true,
                uberRerouteReady: true,
                insuranceSurfaced: true
            ),
            resolved: true,
            rebookingUrl: nil,
            hotelContact: nil,
            uberDeepLink: nil,
            insuranceDocumentId: nil,
            createdAt: dl1423Departure.addingTimeInterval(-90 * 86_400)
        )

        // ===========================================================
        // 4) ACTIVE — NK 622 cancelled on a non-changeable Basic Economy
        //    fare. Alternatives book as NEW tickets, so the dashboard shows
        //    the fare-change warning banner and a "Book" (not "Rebook") CTA.
        // ===========================================================
        let basicEconomyCancel = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .cancellation,
            originalFlight: FlightSnapshot(
                flightNumber: "NK622",
                airline: "Spirit Airlines",
                origin: "LAS",
                destination: "ATL",
                scheduledDeparture: atl(14, hour: 8, minute: 15),
                originalGate: "D54",
                status: "Cancelled — Basic Economy fare, no changes permitted",
                delayMinutes: nil
            ),
            alternatives: [
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "DL 2244",
                    airline: "Delta Air Lines",
                    origin: "LAS",
                    destination: "ATL",
                    departure: atl(14, hour: 11, minute: 20),
                    arrival: atl(14, hour: 17, minute: 45),
                    durationMinutes: 205,
                    price: 356,
                    currency: "USD",
                    availableSeats: 6,
                    cabinClass: "Main",
                    bookingToken: "DL2244-DEMO-004"
                ),
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "AA 1587",
                    airline: "American Airlines",
                    origin: "LAS",
                    destination: "ATL",
                    departure: atl(14, hour: 13, minute: 5),
                    arrival: atl(14, hour: 19, minute: 30),
                    durationMinutes: 205,
                    price: 401,
                    currency: "USD",
                    availableSeats: 3,
                    cabinClass: "Main",
                    bookingToken: "AA1587-DEMO-005"
                )
            ],
            responseActions: ResponseActions(
                alternativesFound: true,
                rebookingChecked: true,
                rebookingEligible: false,
                hotelNotified: false,
                uberRerouteReady: true,
                insuranceSurfaced: true
            ),
            resolved: false,
            rebookingUrl: nil,
            hotelContact: nil,
            uberDeepLink: "uber://?action=setPickup&pickup=my_location",
            insuranceDocumentId: UUID(),
            createdAt: cal.date(byAdding: .minute, value: -12, to: now) ?? now
        )

        let events = [weatherHold, basicEconomyCancel, gateChange, resolvedPast]
        if let data = try? encoder.encode(events) {
            UserDefaults.standard.set(data, forKey: disruptionEventsLocalKey)
        }
    }

    // MARK: - Identity state

    private static func seedIdentityState() {
        if UserDefaults.standard.string(forKey: idStateKey) == nil {
            UserDefaults.standard.set("CA", forKey: idStateKey)
        }
    }

    // MARK: - Helpers

    private static func loadSeededTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Trip].self, from: data)) ?? []
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
