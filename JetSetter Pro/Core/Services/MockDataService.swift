// File: Core/Services/MockDataService.swift
// Provides realistic demo data for all features without real API keys.
// Set isEnabled = false to switch back to live API mode.

import Foundation
import CoreLocation

enum MockDataService {

    // MARK: - Toggle

    /// Master switch — ON = demo mode (seeded persona + mock services),
    /// OFF = beta mode (live APIs, real/empty states). Driven at runtime by the
    /// `DemoMode` toggle in Settings, so a presenter can flip between demo and
    /// beta without a rebuild. Defaults per build: DEBUG → demo, Release/
    /// TestFlight → beta (see `DemoMode.isOn`). 30 read-only call sites depend
    /// on this.
    static var isEnabled: Bool { DemoMode.isOn }

    // MARK: - UserDefaults Key

    // Mock home city used by HomeViewModel when location is unavailable in demo mode
    // (seeded persona: Jordan Ellis, home airport LAS — see IOS_PARITY_NOTES.md §7.1)
    static let mockHomeCity = "Las Vegas"

    // Las Vegas, NV coordinates for live weather in demo mode
    static let mockHomeLat: Double =  36.1699
    static let mockHomeLon: Double = -115.1398

    static let populatedKey = "jetsetterMockPopulated_v6_atlantaPersona"
    private static let bagsStorageKey = "jetsetter_bags"

    // MARK: - Pre-populate Demo Data

    /// Writes sample Trips, Expenses, and Bags to UserDefaults on first launch.
    /// Subsequent calls are no-ops (guarded by populatedKey).
    static func prePopulateIfNeeded() {
        guard isEnabled else { return }
        guard !UserDefaults.standard.bool(forKey: populatedKey) else { return }

        // Fresh demo run — wipe transient flight state so the user can demo
        // check-in again. Bags revert to passive via the seed below.
        CheckInStateStore.resetAll()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let now = Date()
        let cal = Calendar.current

        // ── Trips ──────────────────────────────────────────────────────────────

        func date(addingDays days: Int, hours: Int = 0) -> Date {
            let base = cal.date(byAdding: .day, value: days, to: now) ?? now
            return cal.date(byAdding: .hour, value: hours, to: base) ?? base
        }

        /// Returns now + hours (signed).
        func hoursFromNow(_ hours: Int) -> Date {
            cal.date(byAdding: .hour, value: hours, to: now) ?? now
        }

        // Fixed calendar dates for the seeded persona (IOS_PARITY_NOTES.md §7.1).
        // The primary trip is anchored to Jul 14–17 2026 with a 7:00 AM DL 1423
        // departure; the secondary trip is the Sep 2026 Tokyo Product Summit.
        func atlDate(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = 7; c.day = day; c.hour = hour; c.minute = minute
            return cal.date(from: c) ?? now
        }
        func sepDate(_ day: Int, hour: Int = 0) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = 9; c.day = day; c.hour = hour
            return cal.date(from: c) ?? now
        }

        // ── Atlanta Board Meeting (primary) ───────────────────────────────────
        // Jordan Ellis · DL 1423 LAS → ATL · First · seat 3A · gate C22 · 7:00 AM.
        let atlantaTrip = Trip(
            name: "Atlanta Board Meeting",
            destination: "Atlanta, GA",
            startDate: atlDate(14),
            endDate: atlDate(17, hour: 12),
            items: [
                ItineraryItem(
                    title: "Flight — DL 1423 LAS → ATL",
                    type: .flight,
                    startDate: atlDate(14, hour: 7),
                    endDate: atlDate(14, hour: 14, minute: 35),
                    location: "LAS → ATL",
                    notes: "Gate C22 · Seat 3A · First Class · 7:00 AM departure"
                ),
                ItineraryItem(
                    title: "Check-in — The Ritz-Carlton, Atlanta",
                    type: .hotel,
                    startDate: atlDate(14, hour: 16),
                    endDate: atlDate(17, hour: 11),
                    location: "181 Peachtree St NE, Atlanta, GA",
                    notes: "Executive Suite · Confirmation RC-8842193"
                ),
                ItineraryItem(
                    title: "Q3 Board Meeting",
                    type: .activity,
                    startDate: atlDate(15, hour: 9),
                    endDate: atlDate(15, hour: 17),
                    location: "Atlanta HQ — Executive Boardroom",
                    notes: "Q3 leadership review · full-day session"
                ),
                ItineraryItem(
                    title: "Dinner — Bacchanalia",
                    type: .restaurant,
                    startDate: atlDate(15, hour: 20),
                    location: "1460 Ellsworth Industrial Blvd NW, Atlanta",
                    notes: "Tasting menu · client dinner"
                ),
                ItineraryItem(
                    title: "Return Flight — DL 1876 ATL → LAS",
                    type: .flight,
                    startDate: atlDate(17, hour: 15),
                    endDate: atlDate(17, hour: 17, minute: 10),
                    location: "ATL → LAS",
                    notes: "Seat 3A · First Class"
                )
            ]
        )

        // ── Tokyo Product Summit (secondary, Sep 2026) ────────────────────────
        let tokyoTrip = Trip(
            name: "Tokyo Product Summit",
            destination: "Tokyo, Japan",
            startDate: sepDate(9),
            endDate: sepDate(15),
            items: [
                ItineraryItem(
                    title: "Flight — DL 295 LAS → HND",
                    type: .flight,
                    startDate: sepDate(9, hour: 11),
                    endDate: sepDate(10, hour: 15),
                    location: "LAS → HND",
                    notes: "Seat 3A · Delta One"
                ),
                ItineraryItem(
                    title: "Check-in — Park Hyatt Tokyo",
                    type: .hotel,
                    startDate: sepDate(10, hour: 16),
                    endDate: sepDate(15, hour: 12),
                    location: "3-7-1-2 Nishi Shinjuku, Tokyo",
                    notes: "Park Suite — city view"
                ),
                ItineraryItem(
                    title: "Product Summit 2026",
                    type: .activity,
                    startDate: sepDate(11, hour: 9),
                    endDate: sepDate(13, hour: 18),
                    location: "Tokyo International Forum",
                    notes: "Keynote · Main Stage"
                )
            ]
        )

        if let data = try? encoder.encode([atlantaTrip, tokyoTrip]) {
            UserDefaults.standard.set(data, forKey: "jetsetter_trips")
        }

        // ── Expenses ──────────────────────────────────────────────────────────

        // Atlanta Board Meeting — 4 items totaling $1,812.75 (IOS_PARITY_NOTES.md §7.1).
        let expenses: [Expense] = [
            Expense(amount: 1_290, currency: "USD", category: .transport,
                    merchant: "Delta Air Lines",
                    date: atlDate(14, hour: 7),
                    notes: "DL 1423 airfare — LAS → ATL, First Class"),
            Expense(amount: 412.55, currency: "USD", category: .accommodation,
                    merchant: "The Ritz-Carlton, Atlanta",
                    date: atlDate(14, hour: 16),
                    notes: "Executive Suite — Atlanta Board Meeting"),
            Expense(amount: 86.20, currency: "USD", category: .food,
                    merchant: "Bacchanalia",
                    date: atlDate(15, hour: 20),
                    notes: "Client dinner"),
            Expense(amount: 24, currency: "USD", category: .transport,
                    merchant: "Uber",
                    date: atlDate(15, hour: 8),
                    notes: "Ride to Atlanta HQ")
        ]

        // Expenses are financial data — seed them into the on-device, encrypted
        // SQLite store (device-only, never synced), not UserDefaults.
        FinancialDatabase.shared.replaceAllExpenses(expenses)

        // ── Bags ──────────────────────────────────────────────────────────────
        // On cold open, bags are PASSIVE (registered but not tracking yet).
        // CheckInFlowView calls MockDataService.activateBagsForCheckIn() on
        // successful check-in, which rewrites this list with active states
        // and full scan history — the animations on BagDetailView fire.

        if let data = try? encoder.encode(Self.passiveTokyoBags(now: now)) {
            UserDefaults.standard.set(data, forKey: "jetsetter_bags")
        }

        // ── User Profile ────────────────────────────────────────────────────────
        // Only set if the user hasn't entered a real name yet
        if (UserDefaults.standard.string(forKey: "pref_displayName") ?? "").isEmpty {
            UserDefaults.standard.set("Jordan Ellis", forKey: "pref_displayName")
        }
        // Seed the home airport too (LAS) so the departure loop + profile match.
        if (UserDefaults.standard.string(forKey: "pref_homeAirport") ?? "").isEmpty {
            UserDefaults.standard.set("LAS", forKey: "pref_homeAirport")
        }

        UserDefaults.standard.set(true, forKey: populatedKey)

        // Layer on the richer demo data (wallet, loyalty, IRIS prefs,
        // currency expenses, disruption events, ID state).
        DemoSeeder.seedAll()
    }

    // MARK: - Mock Flights

    static var mockFlights: [Flight] {
        let now = Date()
        return [
            Flight(
                faFlightId: "AAL100-mock",
                ident: "AA100",
                identIata: "AA100",
                operatorName: "American Airlines",
                flightNumber: "100",
                origin: Airport(
                    code: "KJFK", codeIcao: "KJFK", codeIata: "JFK",
                    name: "John F. Kennedy International Airport",
                    city: "New York", timezone: "America/New_York"
                ),
                destination: Airport(
                    code: "EGLL", codeIcao: "EGLL", codeIata: "LHR",
                    name: "Heathrow Airport",
                    city: "London", timezone: "Europe/London"
                ),
                status: "On Time",
                aircraftType: "B77W",
                gateOrigin: "B22",
                gateDestination: "B44",
                terminalOrigin: "8",
                terminalDestination: "3",
                baggageClaim: "7",
                departureDelay: 0,
                arrivalDelay: 0,
                progressPercent: 65,
                cancelled: false,
                diverted: false,
                scheduledOut: now,
                estimatedOut: now,
                actualOut: now,
                scheduledIn: now.addingTimeInterval(25_200),
                estimatedIn: now.addingTimeInterval(25_200),
                actualIn: nil
            ),
            Flight(
                faFlightId: "LH441-mock",
                ident: "LH441",
                identIata: "LH441",
                operatorName: "Lufthansa",
                flightNumber: "441",
                origin: Airport(
                    code: "EDDF", codeIcao: "EDDF", codeIata: "FRA",
                    name: "Frankfurt Airport",
                    city: "Frankfurt", timezone: "Europe/Berlin"
                ),
                destination: Airport(
                    code: "KJFK", codeIcao: "KJFK", codeIata: "JFK",
                    name: "John F. Kennedy International Airport",
                    city: "New York", timezone: "America/New_York"
                ),
                status: "Delayed",
                aircraftType: "A350",
                gateOrigin: "A58",
                gateDestination: "B22",
                terminalOrigin: "A",
                terminalDestination: "1",
                baggageClaim: "5",
                departureDelay: 2_700,
                arrivalDelay: 2_700,
                progressPercent: 0,
                cancelled: false,
                diverted: false,
                scheduledOut: now,
                estimatedOut: now.addingTimeInterval(2_700),
                actualOut: nil,
                scheduledIn: now.addingTimeInterval(32_400),
                estimatedIn: now.addingTimeInterval(35_100),
                actualIn: nil
            )
        ]
    }

    // MARK: - Mock Hotels

    static var mockHotels: [HotelProperty] {
        [
            HotelProperty(
                propertyId: "mock_fourseasons",
                name: "Four Seasons Hotel",
                status: "available",
                score: 4.95,
                rooms: [
                    HotelRoom(id: "fs_king", roomName: "Deluxe King Room", rates: [
                        RoomRate(id: "fs_r1", availableRooms: 2, refundable: true,
                                 nightlyCost: RateCost(value: "785", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "864", currency: "USD"))
                    ]),
                    HotelRoom(id: "fs_premier", roomName: "Premier Suite", rates: [
                        RoomRate(id: "fs_r2", availableRooms: 1, refundable: false,
                                 nightlyCost: RateCost(value: "1850", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "2035", currency: "USD"))
                    ])
                ]
            ),
            HotelProperty(
                propertyId: "mock_ritz",
                name: "The Ritz-Carlton",
                status: "available",
                score: 4.92,
                rooms: [
                    HotelRoom(id: "ritz_sup", roomName: "Superior Room", rates: [
                        RoomRate(id: "ritz_r1", availableRooms: 4, refundable: true,
                                 nightlyCost: RateCost(value: "620", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "682", currency: "USD"))
                    ]),
                    HotelRoom(id: "ritz_club", roomName: "Club Level Suite", rates: [
                        RoomRate(id: "ritz_r2", availableRooms: 2, refundable: true,
                                 nightlyCost: RateCost(value: "1240", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "1364", currency: "USD"))
                    ])
                ]
            ),
            HotelProperty(
                propertyId: "mock_1hotel",
                name: "1 Hotel Central Park",
                status: "available",
                score: 4.87,
                rooms: [
                    HotelRoom(id: "1h_nature", roomName: "Nature Room", rates: [
                        RoomRate(id: "1h_r1", availableRooms: 5, refundable: true,
                                 nightlyCost: RateCost(value: "495", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "545", currency: "USD"))
                    ]),
                    HotelRoom(id: "1h_terrace", roomName: "Park Terrace Suite", rates: [
                        RoomRate(id: "1h_r2", availableRooms: 1, refundable: false,
                                 nightlyCost: RateCost(value: "980", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "1078", currency: "USD"))
                    ])
                ]
            ),
            HotelProperty(
                propertyId: "mock_peninsula",
                name: "The Peninsula",
                status: "available",
                score: 4.90,
                rooms: [
                    HotelRoom(id: "pen_dlx", roomName: "Deluxe Room", rates: [
                        RoomRate(id: "pen_r1", availableRooms: 3, refundable: true,
                                 nightlyCost: RateCost(value: "710", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "782", currency: "USD"))
                    ]),
                    HotelRoom(id: "pen_ph", roomName: "Penthouse Suite", rates: [
                        RoomRate(id: "pen_r2", availableRooms: 1, refundable: false,
                                 nightlyCost: RateCost(value: "4200", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "4620", currency: "USD"))
                    ])
                ]
            ),
            HotelProperty(
                propertyId: "mock_parkhyatt",
                name: "Park Hyatt",
                status: "available",
                score: 4.85,
                rooms: [
                    HotelRoom(id: "ph_park", roomName: "Park Room", rates: [
                        RoomRate(id: "ph_r1", availableRooms: 6, refundable: true,
                                 nightlyCost: RateCost(value: "420", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "462", currency: "USD"))
                    ]),
                    HotelRoom(id: "ph_suite", roomName: "Park Suite", rates: [
                        RoomRate(id: "ph_r2", availableRooms: 2, refundable: true,
                                 nightlyCost: RateCost(value: "890", currency: "USD"),
                                 inclusiveTotal: RateCost(value: "979", currency: "USD"))
                    ])
                ]
            )
        ]
    }

    // MARK: - Mock Ride Options

    static var mockRideOptions: [RideOption] {
        [
            RideOption(
                id: "uber-black",
                provider: .uber,
                productName: "Uber Black",
                priceRange: "$38–$46",
                estimatedMinutes: 4,
                isSurging: false
            ),
            RideOption(
                id: "uber-black-suv",
                provider: .uber,
                productName: "Uber Black SUV",
                priceRange: "$52–$68",
                estimatedMinutes: 7,
                isSurging: false
            ),
            RideOption(
                id: "uberx",
                provider: .uber,
                productName: "UberX",
                priceRange: "$18–$24",
                estimatedMinutes: 3,
                isSurging: false
            ),
            RideOption(
                id: "lyft-lux-black",
                provider: .lyft,
                productName: "Lyft Lux Black",
                priceRange: "$41–$52",
                estimatedMinutes: 5,
                isSurging: false
            ),
            RideOption(
                id: "lyft-lux-black-xl",
                provider: .lyft,
                productName: "Lyft Lux Black XL",
                priceRange: "$56–$72",
                estimatedMinutes: 8,
                isSurging: true
            )
        ]
    }

    // MARK: - Mock AI Assistant Responses

    /// Returns a curated executive-level response matched to message keywords.
    static func mockAssistantResponse(for message: String) -> String {
        let lower = message.lowercased()

        if lower.contains("flight") || lower.contains("dl 1423") || lower.contains("dl1423") || lower.contains("delay") || lower.contains("gate") {
            return """
            Your **DL 1423** (LAS → ATL) departs **7:00 AM** from **Gate C22** — **Seat 3A, First Class**.

            I'm watching it for weather at ATL. If anything shifts, I'll surface same-day alternatives and update your leave-by time automatically.

            Would you like me to set a gate reminder or pull up your leave-by time?
            """
        }

        if lower.contains("hotel") || lower.contains("check in") || lower.contains("room") || lower.contains("stay") {
            return """
            You're booked at **The Ritz-Carlton, Atlanta** for the board meeting — confirmation **RC-8842193**.

            - 181 Peachtree St NE, Atlanta, GA
            - Check-in **Jul 14**, check-out **Jul 17**
            - Executive Suite

            Want me to add a late-arrival note or arrange a car to the hotel?
            """
        }

        if lower.contains("ride") || lower.contains("uber") || lower.contains("lyft") || lower.contains("transport") || lower.contains("car service") {
            return """
            I've found rides for your trip:

            - **Uber Black** — 4 min away · $38–$46
            - **Lyft Lux Black** — 5 min away · $41–$52
            - **Uber Black SUV** — 7 min away · $52–$68

            No surge pricing on Uber Black right now. Tap any option in the Ground Transport tab to book right here in the app.
            """
        }

        if lower.contains("expense") || lower.contains("budget") || lower.contains("spend") || lower.contains("cost") {
            return """
            Your **Atlanta Board Meeting** expenses to date:

            | Category | Amount |
            |---|---|
            | Delta airfare | $1,290.00 |
            | The Ritz-Carlton | $412.55 |
            | Bacchanalia | $86.20 |
            | Uber | $24.00 |
            | **Total** | **$1,812.75** |

            Everything's categorized and ready to export whenever you are.
            """
        }

        if lower.contains("luggage") || lower.contains("bag") || lower.contains("baggage") || lower.contains("suitcase") {
            return """
            Current **luggage status** for **DL 1423**:

            🧳 **Rimowa Original** — On Aircraft · Cargo Hold 2 · 1 min ago
            👜 **Tumi Carry-On** — Cabin · Overhead Bin 4A · 2 min ago
            👔 **Brioni Suit Carrier** — On Belt · Sort facility · 3 min ago

            AirTag-equipped bags are tracking normally. Everything's loaded for your LAS → ATL departure.
            """
        }

        if lower.contains("itinerary") || lower.contains("schedule") || lower.contains("plan") || lower.contains("trip") {
            return """
            Your **Atlanta Board Meeting** itinerary:

            **Jul 14** — DL 1423 LAS → ATL · 7:00 AM · Gate C22 · Seat 3A · First Class
            **Jul 14** — Check-in The Ritz-Carlton, Atlanta · 4:00 PM
            **Jul 15** — Q3 Board Meeting · Executive Boardroom · 9:00 AM
            **Jul 15** — Dinner at Bacchanalia · 8:00 PM
            **Jul 17** — Check-out · DL 1876 ATL → LAS · 3:00 PM

            Coming up: **Tokyo Product Summit** in September. Review that itinerary?
            """
        }

        if lower.contains("lounge") || lower.contains("sky club") || lower.contains("centurion") {
            return """
            With your **Delta Sky Club** and **Centurion** access:

            **LAS (Harry Reid):**
            - Delta Sky Club (Concourse D — opens 4:30 AM)
            - Centurion Lounge (opens 5:00 AM)

            **ATL (Hartsfield-Jackson):**
            - Delta Sky Club — multiple Concourse locations

            Shall I add lounge details to your pre-departure checklist?
            """
        }

        if lower.contains("weather") || lower.contains("forecast") || lower.contains("temperature") {
            return """
            **Departure conditions at LAS:** Clear skies · **74°F** · light winds — great for an on-time 7:00 AM push.

            **Atlanta this week:** warm and humid, mid-80s°F, with scattered afternoon storms. I'm monitoring ATL for any weather holds that could affect DL 1423.

            Want me to set a weather alert for your departure day?
            """
        }

        // Default
        return """
        I'm your **Jetsetter Pro** executive travel assistant. I can help you with:

        - ✈️ **Flights** — real-time status, gate info, and delay alerts
        - 🏨 **Hotels** — premium property availability and booking
        - 🚗 **Ground Transport** — Uber Black & Lyft Lux estimates
        - 💰 **Expenses** — categorize, track, and report travel spend
        - 🧳 **Luggage** — real-time bag location and status
        - 📋 **Itinerary** — trip planning with Calendar sync

        What would you like help with for your upcoming trip?
        """
    }

    // MARK: - Bag Activation (Check-In Wired)

    /// Passive baseline — bags are registered but not yet tracking.
    /// Status `.checkedIn`, no scan history, no last location.
    static func passiveTokyoBags(now: Date = Date()) -> [Bag] {
        [
            Bag(
                nickname: "Rimowa Original Cabin",
                description: "Silver aluminum hard-shell — large",
                airline: "Delta Air Lines",
                flightNumber: "DL1423",
                bagTagNumber: "0012345678",
                hasAirTag: true,
                status: .checkedIn,
                lastLocation: "Awaiting first scan",
                lastChecked: nil,
                scanHistory: []
            ),
            Bag(
                nickname: "Tumi Alpha Carry-On",
                description: "Black carry-on, Tumi Alpha 3",
                airline: "Delta Air Lines",
                flightNumber: "DL1423",
                hasAirTag: false,
                status: .checkedIn,
                lastLocation: "Awaiting first scan",
                lastChecked: nil,
                scanHistory: []
            ),
            Bag(
                nickname: "Brioni Suit Carrier",
                description: "Navy garment bag — Brioni",
                airline: "Delta Air Lines",
                flightNumber: "DL1423",
                bagTagNumber: "0012345679",
                hasAirTag: true,
                status: .checkedIn,
                lastLocation: "Awaiting first scan",
                lastChecked: nil,
                scanHistory: []
            ),
            Bag(
                nickname: "Bottega Veneta Weekender",
                description: "Tan intrecciato leather weekender",
                airline: "Delta Air Lines",
                flightNumber: "DL1423",
                bagTagNumber: "0012345680",
                hasAirTag: true,
                status: .checkedIn,
                lastLocation: "Awaiting first scan",
                lastChecked: nil,
                scanHistory: []
            )
        ]
    }

    /// Active state with full scan history and per-bag status — what shows
    /// AFTER the user completes check-in via CheckInFlowView.
    static func activeTokyoBags(now: Date = Date()) -> [Bag] {
        let cal = Calendar.current
        func minsAgo(_ m: Int) -> Date { cal.date(byAdding: .minute, value: -m, to: now) ?? now }
        func hoursAgo(_ h: Int, _ m: Int = 0) -> Date {
            let base = cal.date(byAdding: .hour, value: -h, to: now) ?? now
            return cal.date(byAdding: .minute, value: -m, to: base) ?? base
        }

        let rimowaHistory: [BagScanEvent] = [
            BagScanEvent(timestamp: minsAgo(15), location: "JFK Terminal 8 — Counter scan",
                         scanType: .checkIn, note: "Tagged with priority handling"),
            BagScanEvent(timestamp: minsAgo(12), location: "JFK Belt 7 — Outbound sort",
                         scanType: .onBelt, note: nil),
            BagScanEvent(timestamp: minsAgo(8), location: "JFK Sort Facility — Bay 12",
                         scanType: .onBelt, note: nil),
            BagScanEvent(timestamp: minsAgo(4), location: "JFK Loader B12 — Conveyor 3",
                         scanType: .loaderTransfer, note: nil),
            BagScanEvent(timestamp: minsAgo(1), location: "DL1423 Cargo Hold 2 — Secured",
                         scanType: .securedInCargo, note: "Secured for departure")
        ]

        let tumiHistory: [BagScanEvent] = [
            BagScanEvent(timestamp: minsAgo(14), location: "JFK Terminal 8 — Counter scan",
                         scanType: .checkIn, note: "Carry-on tagged at gate"),
            BagScanEvent(timestamp: minsAgo(10), location: "JFK Gate B14 — Boarding agent scan",
                         scanType: .claimed, note: nil),
            BagScanEvent(timestamp: minsAgo(6), location: "DL1423 Overhead Bin 4A",
                         scanType: .claimed, note: "Stowed for cabin"),
            BagScanEvent(timestamp: minsAgo(2), location: "DL1423 — Cabin secured",
                         scanType: .claimed, note: "Ready for pushback")
        ]

        let brioniHistory: [BagScanEvent] = [
            BagScanEvent(timestamp: minsAgo(15), location: "JFK Terminal 8 — Counter scan",
                         scanType: .checkIn, note: nil),
            BagScanEvent(timestamp: minsAgo(11), location: "JFK Belt 7 — Outbound sort",
                         scanType: .onBelt, note: nil),
            BagScanEvent(timestamp: minsAgo(3), location: "JFK Belt 7 — Sort facility",
                         scanType: .onBelt, note: "Currently moving on belt")
        ]

        let bottegaHistory: [BagScanEvent] = [
            BagScanEvent(timestamp: minsAgo(15), location: "JFK Terminal 8 — Counter scan",
                         scanType: .checkIn, note: nil),
            BagScanEvent(timestamp: minsAgo(10), location: "JFK Belt 7 — Outbound sort",
                         scanType: .onBelt, note: nil),
            BagScanEvent(timestamp: minsAgo(1), location: "JFK Loader B12 — Conveyor 3",
                         scanType: .loaderTransfer, note: "Currently loading onto aircraft")
        ]

        return [
            Bag(nickname: "Rimowa Original Cabin",
                description: "Silver aluminum hard-shell — large",
                airline: "Delta Air Lines", flightNumber: "DL1423",
                bagTagNumber: "0012345678", hasAirTag: true,
                status: .onAircraft,
                lastLocation: "DL1423 Cargo Hold 2",
                lastChecked: minsAgo(1),
                scanHistory: rimowaHistory),
            Bag(nickname: "Tumi Alpha Carry-On",
                description: "Black carry-on, Tumi Alpha 3",
                airline: "Delta Air Lines", flightNumber: "DL1423",
                hasAirTag: false,
                status: .delivered,
                lastLocation: "DL1423 Overhead Bin 4A",
                lastChecked: minsAgo(2),
                scanHistory: tumiHistory),
            Bag(nickname: "Brioni Suit Carrier",
                description: "Navy garment bag — Brioni",
                airline: "Delta Air Lines", flightNumber: "DL1423",
                bagTagNumber: "0012345679", hasAirTag: true,
                status: .onBelt,
                lastLocation: "JFK Belt 7 — Sort facility",
                lastChecked: minsAgo(3),
                scanHistory: brioniHistory),
            Bag(nickname: "Bottega Veneta Weekender",
                description: "Tan intrecciato leather weekender",
                airline: "Delta Air Lines", flightNumber: "DL1423",
                bagTagNumber: "0012345680", hasAirTag: true,
                status: .loading,
                lastLocation: "JFK Loader B12",
                lastChecked: minsAgo(1),
                scanHistory: bottegaHistory)
        ]
    }

    /// Called by CheckInFlowView's success step right after `markCheckedIn`.
    /// Rewrites the bag list to the active state with scan history, and posts
    /// `.jetSetterBagsActivated` so any open Luggage view reloads immediately.
    static func activateBagsForCheckIn() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(activeTokyoBags()) {
            UserDefaults.standard.set(data, forKey: bagsStorageKey)
        }
        NotificationCenter.default.post(name: .jetSetterBagsActivated, object: nil)
    }
}

extension Notification.Name {
    /// Posted when CheckInFlowView completes check-in — Luggage view reloads
    /// bags from UserDefaults so the new active states + scan history appear.
    static let jetSetterBagsActivated = Notification.Name("jetSetterBagsActivated")
}
