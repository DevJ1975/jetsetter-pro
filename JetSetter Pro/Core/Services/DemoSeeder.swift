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
    // fallbacks added so they don't need a Supabase sign-in to display data).
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
        let tokyoTrip  = trips.first { $0.name.contains("Tokyo") }
        let dubaiTrip  = trips.first { $0.name.contains("Dubai") }
        let bostonTrip = trips.first { $0.name.contains("Boston") }

        seedWalletItems(tokyoTrip: tokyoTrip, dubaiTrip: dubaiTrip, bostonTrip: bostonTrip)
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

    private static func seedWalletItems(tokyoTrip: Trip?, dubaiTrip: Trip?, bostonTrip: Trip?) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let now = Date()
        let cal = Calendar.current
        let plus = { (days: Int) in cal.date(byAdding: .day, value: days, to: now) ?? now }
        let plusHours = { (hours: Int) in cal.date(byAdding: .hour, value: hours, to: now) ?? now }

        // Boston return flight departs tomorrow 4:30 PM. Anchor it to
        // "today + 1 day at 16:30 local" so the wallet card reads naturally.
        let bostonReturnDate: Date = {
            var comps = cal.dateComponents([.year, .month, .day], from: plus(1))
            comps.hour = 16
            comps.minute = 30
            return cal.date(from: comps) ?? plusHours(28)
        }()
        // Mandarin Oriental check-out tomorrow 11 AM
        let bostonCheckoutDate: Date = {
            var comps = cal.dateComponents([.year, .month, .day], from: plus(1))
            comps.hour = 11
            comps.minute = 0
            return cal.date(from: comps) ?? plusHours(23)
        }()

        let items: [WalletItem] = [
            // Boston return-leg boarding pass (active trip)
            WalletItem(
                tripId: bostonTrip?.id,
                itemType: .boardingPass,
                title: "DL2244 · BOS → JFK",
                confirmationNumber: "DLBPCH",
                date: bostonReturnDate,
                rawData: [
                    "airline": "Delta Air Lines",
                    "flight_number": "DL2244",
                    "iata_code": "DL",
                    "departure_airport": "BOS",
                    "arrival_airport": "JFK",
                    "seat_number": "1A",
                    "gate": "B27",
                    "terminal": "A"
                ]
            ),
            // Mandarin Oriental Boston (checked-in already)
            WalletItem(
                tripId: bostonTrip?.id,
                itemType: .hotelReservation,
                title: "Mandarin Oriental Boston",
                confirmationNumber: "MO-2026-44910",
                date: plusHours(-22),
                rawData: [
                    "hotel_address": "776 Boylston St, Boston, MA",
                    "check_in_date": isoString(plusHours(-22)),
                    "check_out_date": isoString(bostonCheckoutDate),
                    "end_date": isoString(bostonCheckoutDate)
                ]
            ),
            // Tokyo outbound boarding pass — departs TONIGHT
            WalletItem(
                tripId: tokyoTrip?.id,
                itemType: .boardingPass,
                title: "AA169 · JFK → NRT",
                confirmationNumber: "JLXRAY",
                date: plusHours(18),
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
            // Tokyo return boarding pass — re-anchored to +9d
            WalletItem(
                tripId: tokyoTrip?.id,
                itemType: .boardingPass,
                title: "AA170 · NRT → JFK",
                confirmationNumber: "JLXRAY",
                date: plus(9),
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
            // Park Hyatt Tokyo — arrival tomorrow afternoon (~NRT + 2h transfer)
            WalletItem(
                tripId: tokyoTrip?.id,
                itemType: .hotelReservation,
                title: "Park Hyatt Tokyo",
                confirmationNumber: "PHT-2026-78451",
                date: plus(1),
                rawData: [
                    "hotel_address": "3-7-1-2 Nishi Shinjuku, Tokyo",
                    "check_in_date": isoString(plus(1)),
                    "check_out_date": isoString(plus(9)),
                    "end_date": isoString(plus(9))
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
                date: plus(1),
                rawData: [
                    "rental_company": "Hertz",
                    "pickup_location": "NRT Airport — Premier Counter",
                    "vehicle_class": "Lexus ES Hybrid",
                    "end_date": isoString(plus(9))
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
        let hoursFromNow: (Int) -> Date = { cal.date(byAdding: .hour, value: $0, to: now) ?? now }
        let daysFromNow: (Int) -> Date = { cal.date(byAdding: .day, value: $0, to: now) ?? now }

        // Tokyo departure anchor — matches the AA169 wallet boarding pass (+18h).
        let aa169Departure = hoursFromNow(18)

        // ===========================================================
        // 1) LEAD ACTIVE — AA169 typhoon major delay (created 2h ago)
        // ===========================================================
        let typhoonDelay = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .majorDelay,
            originalFlight: FlightSnapshot(
                flightNumber: "AA169",
                airline: "American Airlines",
                origin: "JFK",
                destination: "NRT",
                scheduledDeparture: aa169Departure,
                originalGate: "B22",
                status: "Typhoon Mawar — ATC ground stop in effect at JFK",
                delayMinutes: 215
            ),
            alternatives: [
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "JL005",
                    airline: "Japan Airlines",
                    origin: "JFK",
                    destination: "NRT",
                    departure: hoursFromNow(30),
                    arrival: hoursFromNow(43),
                    durationMinutes: 780,
                    price: 1_485,
                    currency: "USD",
                    availableSeats: 7,
                    cabinClass: "Business",
                    bookingToken: "JL5-DEMO-001"
                ),
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "DL181",
                    airline: "Delta",
                    origin: "JFK",
                    destination: "HND",
                    departure: hoursFromNow(24),
                    arrival: hoursFromNow(38),
                    durationMinutes: 840,
                    price: 1_320,
                    currency: "USD",
                    availableSeats: 12,
                    cabinClass: "Business",
                    bookingToken: "DL181-DEMO-002"
                ),
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "NH009",
                    airline: "ANA",
                    origin: "JFK",
                    destination: "NRT",
                    departure: hoursFromNow(36),
                    arrival: hoursFromNow(50),
                    durationMinutes: 840,
                    price: 1_690,
                    currency: "USD",
                    availableSeats: 3,
                    cabinClass: "Business",
                    bookingToken: "NH9-DEMO-003"
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
            rebookingUrl: "https://aa.com/rebook",
            hotelContact: "+81-3-5322-1234",
            uberDeepLink: "uber://?action=setPickup&pickup=my_location",
            insuranceDocumentId: UUID(),
            createdAt: cal.date(byAdding: .hour, value: -2, to: now) ?? now
        )

        // ===========================================================
        // 2) SECONDARY ACTIVE — AA169 gate change (created 45m ago)
        // ===========================================================
        let gateChange = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .gateChange,
            originalFlight: FlightSnapshot(
                flightNumber: "AA169",
                airline: "American Airlines",
                origin: "JFK",
                destination: "NRT",
                scheduledDeparture: aa169Departure,
                originalGate: "B22",
                status: "Gate B22 → B14 · 12-min walk via Terminal 8 connector",
                delayMinutes: nil
            ),
            alternatives: [
                AlternativeFlight(
                    id: UUID(),
                    flightNumber: "AA171",
                    airline: "American Airlines",
                    origin: "JFK",
                    destination: "NRT",
                    departure: cal.date(byAdding: .hour, value: 1, to: aa169Departure) ?? aa169Departure,
                    arrival: cal.date(byAdding: .hour, value: 15, to: aa169Departure) ?? aa169Departure,
                    durationMinutes: 840,
                    price: 0,
                    currency: "USD",
                    availableSeats: 4,
                    cabinClass: "Business",
                    bookingToken: "AA171-SAMEDAY"
                )
            ],
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
            uberDeepLink: "uber://?action=setPickup&pickup=my_location&dropoff[formatted_address]=JFK%20Terminal%208%20Gate%20B14",
            insuranceDocumentId: nil,
            createdAt: cal.date(byAdding: .minute, value: -45, to: now) ?? now
        )

        // ===========================================================
        // 3) RESOLVED — EK201 sandstorm delay (2 weeks ago)
        // ===========================================================
        let sandstorm = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .majorDelay,
            originalFlight: FlightSnapshot(
                flightNumber: "EK201",
                airline: "Emirates",
                origin: "JFK",
                destination: "DXB",
                scheduledDeparture: daysFromNow(-14),
                originalGate: "C45",
                status: "Sandstorm at DXB — held 95 min, departed 5:35 AM",
                delayMinutes: 95
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
            createdAt: daysFromNow(-14)
        )

        // ===========================================================
        // 4) RESOLVED — BA178 cancellation (4 weeks ago, kept as-is)
        // ===========================================================
        let baCancellation = DisruptionEvent(
            id: UUID(),
            userId: "demo-user",
            tripId: tripID,
            eventType: .cancellation,
            originalFlight: FlightSnapshot(
                flightNumber: "BA178",
                airline: "British Airways",
                origin: "JFK",
                destination: "LHR",
                scheduledDeparture: daysFromNow(-28),
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
                    departure: daysFromNow(-28).addingTimeInterval(3 * 3600),
                    arrival: daysFromNow(-27).addingTimeInterval(11 * 3600),
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
            createdAt: daysFromNow(-28)
        )

        let events = [typhoonDelay, gateChange, sandstorm, baCancellation]
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
