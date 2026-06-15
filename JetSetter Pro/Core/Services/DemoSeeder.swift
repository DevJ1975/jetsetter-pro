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
        let tokyoTrip = trips.first { $0.name.contains("Tokyo") }
        let dubaiTrip = trips.first { $0.name.contains("Dubai") }

        seedWalletItems(tokyoTrip: tokyoTrip, dubaiTrip: dubaiTrip)
        seedLoyaltyAccounts()
        seedIRISMemory()
        if let tokyoTrip = tokyoTrip {
            seedCurrencyExpenses(tripID: tokyoTrip.id)
            seedDisruptionEvents(tripID: tokyoTrip.id)
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
            "jetsetterMockPopulated_v2"
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

    private static func seedWalletItems(tokyoTrip: Trip?, dubaiTrip: Trip?) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let now = Date()
        let cal = Calendar.current
        let plus = { (days: Int) in cal.date(byAdding: .day, value: days, to: now) ?? now }

        let items: [WalletItem] = [
            // Tokyo outbound boarding pass
            WalletItem(
                tripId: tokyoTrip?.id,
                itemType: .boardingPass,
                title: "AA169 · JFK → NRT",
                confirmationNumber: "JLXRAY",
                date: plus(3),
                rawData: [
                    "airline": "American Airlines",
                    "flight_number": "AA169",
                    "iata_code": "AA",
                    "departure_airport": "JFK",
                    "arrival_airport": "NRT",
                    "seat_number": "3A",
                    "gate": "B22",
                    "terminal": "8"
                ]
            ),
            // Tokyo return boarding pass
            WalletItem(
                tripId: tokyoTrip?.id,
                itemType: .boardingPass,
                title: "AA170 · NRT → JFK",
                confirmationNumber: "JLXRAY",
                date: plus(10),
                rawData: [
                    "airline": "American Airlines",
                    "flight_number": "AA170",
                    "iata_code": "AA",
                    "departure_airport": "NRT",
                    "arrival_airport": "JFK",
                    "seat_number": "2A",
                    "gate": "C14",
                    "terminal": "1"
                ]
            ),
            // Dubai outbound boarding pass
            WalletItem(
                tripId: dubaiTrip?.id,
                itemType: .boardingPass,
                title: "EK201 · JFK → DXB",
                confirmationNumber: "EK-9821-AD",
                date: plus(21),
                rawData: [
                    "airline": "Emirates",
                    "flight_number": "EK201",
                    "iata_code": "EK",
                    "departure_airport": "JFK",
                    "arrival_airport": "DXB",
                    "seat_number": "1K",
                    "gate": "B2",
                    "terminal": "4"
                ]
            ),
            // Park Hyatt Tokyo
            WalletItem(
                tripId: tokyoTrip?.id,
                itemType: .hotelReservation,
                title: "Park Hyatt Tokyo",
                confirmationNumber: "PHT-2026-78451",
                date: plus(4),
                rawData: [
                    "hotel_address": "3-7-1-2 Nishi Shinjuku, Tokyo",
                    "check_in_date": isoString(plus(4)),
                    "check_out_date": isoString(plus(10)),
                    "end_date": isoString(plus(10))
                ]
            ),
            // Burj Al Arab
            WalletItem(
                tripId: dubaiTrip?.id,
                itemType: .hotelReservation,
                title: "Burj Al Arab — Royal Suite",
                confirmationNumber: "BAA-2026-19284",
                date: plus(22),
                rawData: [
                    "hotel_address": "Jumeirah St, Dubai",
                    "check_in_date": isoString(plus(22)),
                    "check_out_date": isoString(plus(26)),
                    "end_date": isoString(plus(26))
                ]
            ),
            // Hertz car rental at Narita
            WalletItem(
                tripId: tokyoTrip?.id,
                itemType: .carRental,
                title: "Hertz Premier — NRT pickup",
                confirmationNumber: "HZ-7821-TKY",
                date: plus(4),
                rawData: [
                    "rental_company": "Hertz",
                    "pickup_location": "NRT Airport — Premier Counter",
                    "vehicle_class": "Lexus ES Hybrid",
                    "end_date": isoString(plus(10))
                ]
            ),
            // Travel insurance
            WalletItem(
                itemType: .travelInsurance,
                title: "Allianz Premium Travel",
                confirmationNumber: "ALZ-AT-9128340",
                date: now,
                rawData: [
                    "provider": "Allianz Global Assistance",
                    "policy_number": "AT-9128340-IK",
                    "coverage_type": "Premium — Annual Multi-Trip"
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
                tierExpiration: nowPlus(4)
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

        // ACTIVE: return flight delayed
        let active = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .majorDelay,
            originalFlight: FlightSnapshot(
                flightNumber: "AA170",
                airline: "American Airlines",
                origin: "NRT",
                destination: "JFK",
                scheduledDeparture: cal.date(byAdding: .day, value: 10, to: now) ?? now,
                originalGate: "C14",
                status: "Delayed",
                delayMinutes: 45
            ),
            alternatives: [
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "JL004",
                    airline: "Japan Airlines",
                    origin: "NRT",
                    destination: "JFK",
                    departure: cal.date(byAdding: .hour, value: 240, to: now) ?? now,
                    arrival: cal.date(byAdding: .hour, value: 252, to: now) ?? now,
                    durationMinutes: 720,
                    price: 1_485,
                    currency: "USD",
                    availableSeats: 6,
                    cabinClass: "Business",
                    bookingToken: "OFFER_JL004_DEMO"
                ),
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "DL182",
                    airline: "Delta Air Lines",
                    origin: "NRT",
                    destination: "JFK",
                    departure: cal.date(byAdding: .hour, value: 244, to: now) ?? now,
                    arrival: cal.date(byAdding: .hour, value: 257, to: now) ?? now,
                    durationMinutes: 780,
                    price: 1_320,
                    currency: "USD",
                    availableSeats: 12,
                    cabinClass: "Business",
                    bookingToken: "OFFER_DL182_DEMO"
                ),
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "NH008",
                    airline: "ANA",
                    origin: "NRT",
                    destination: "JFK",
                    departure: cal.date(byAdding: .hour, value: 248, to: now) ?? now,
                    arrival: cal.date(byAdding: .hour, value: 261, to: now) ?? now,
                    durationMinutes: 780,
                    price: 1_690,
                    currency: "USD",
                    availableSeats: 3,
                    cabinClass: "Business",
                    bookingToken: "OFFER_NH008_DEMO"
                )
            ],
            responseActions: ResponseActions(
                alternativesFound: true,
                rebookingChecked: true,
                hotelNotified: true,
                uberRerouteReady: true,
                insuranceSurfaced: true
            ),
            resolved: false,
            rebookingUrl: "https://www.amadeus.com/offers/OFFER_DL182_DEMO",
            hotelContact: "reservations@parkhyatt.com",
            uberDeepLink: "uber://?action=setPickup&pickup=my_location",
            insuranceDocumentId: nil,
            createdAt: cal.date(byAdding: .hour, value: -2, to: now) ?? now
        )

        // RESOLVED: past BA cancellation
        let resolved = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .cancellation,
            originalFlight: FlightSnapshot(
                flightNumber: "BA178",
                airline: "British Airways",
                origin: "JFK",
                destination: "LHR",
                scheduledDeparture: cal.date(byAdding: .day, value: -28, to: now) ?? now,
                originalGate: "B47",
                status: "Cancelled",
                delayMinutes: nil
            ),
            alternatives: [
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "VS4",
                    airline: "Virgin Atlantic",
                    origin: "JFK",
                    destination: "LHR",
                    departure: cal.date(byAdding: .day, value: -28, to: now)?.addingTimeInterval(3 * 3600) ?? now,
                    arrival: cal.date(byAdding: .day, value: -27, to: now)?.addingTimeInterval(11 * 3600) ?? now,
                    durationMinutes: 420,
                    price: 985,
                    currency: "USD",
                    availableSeats: 8,
                    cabinClass: "Premium Economy",
                    bookingToken: "OFFER_VS4_PAST"
                )
            ],
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
            createdAt: cal.date(byAdding: .day, value: -28, to: now) ?? now
        )

        if let data = try? encoder.encode([active, resolved]) {
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
