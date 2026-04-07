// File: Core/Services/MockDataService.swift
// Provides realistic demo data for all features without real API keys.
// Set isEnabled = false to switch back to live API mode.

import Foundation
import CoreLocation

enum MockDataService {

    // MARK: - Toggle

    /// Master switch. Set to false once real API keys are configured.
    static let isEnabled = true

    // MARK: - UserDefaults Key

    private static let populatedKey = "jetsetterMockPopulated_v1"

    // MARK: - Pre-populate Demo Data

    /// Writes sample Trips, Expenses, and Bags to UserDefaults on first launch.
    /// Subsequent calls are no-ops (guarded by populatedKey).
    static func prePopulateIfNeeded() {
        guard isEnabled else { return }
        guard !UserDefaults.standard.bool(forKey: populatedKey) else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let now = Date()
        let cal = Calendar.current

        // ── Trips ──────────────────────────────────────────────────────────────

        func date(addingDays days: Int, hours: Int = 0) -> Date {
            let base = cal.date(byAdding: .day, value: days, to: now) ?? now
            return cal.date(byAdding: .hour, value: hours, to: base) ?? base
        }

        let tokyoTrip = Trip(
            name: "Tokyo Business Summit",
            destination: "Tokyo, Japan",
            startDate: date(addingDays: 3),
            endDate: date(addingDays: 10),
            items: [
                ItineraryItem(
                    title: "Flight — AA169 JFK → NRT",
                    type: .flight,
                    startDate: date(addingDays: 3, hours: 23),
                    endDate: date(addingDays: 4, hours: 13),
                    location: "JFK → NRT",
                    notes: "Gate B22 · Seat 3A · Boeing 787-9 · Business"
                ),
                ItineraryItem(
                    title: "Check-in — Park Hyatt Tokyo",
                    type: .hotel,
                    startDate: date(addingDays: 4, hours: 15),
                    endDate: date(addingDays: 10, hours: 12),
                    location: "3-7-1-2 Nishi Shinjuku, Tokyo",
                    notes: "Park Suite — 48th floor · City view"
                ),
                ItineraryItem(
                    title: "Global Innovators Summit 2025",
                    type: .activity,
                    startDate: date(addingDays: 5, hours: 9),
                    endDate: date(addingDays: 7, hours: 18),
                    location: "Tokyo International Forum",
                    notes: "Keynote speaker: Day 1 · 10:00 AM Main Stage"
                ),
                ItineraryItem(
                    title: "Dinner — Sukiyabashi Jiro",
                    type: .restaurant,
                    startDate: date(addingDays: 6, hours: 20),
                    location: "Chuo City, Tokyo",
                    notes: "Reservation for 4 · Omakase · Business attire"
                ),
                ItineraryItem(
                    title: "Return Flight — AA170 NRT → JFK",
                    type: .flight,
                    startDate: date(addingDays: 10, hours: 18),
                    endDate: date(addingDays: 11, hours: 16),
                    location: "NRT → JFK",
                    notes: "Gate C14 · Seat 2A · First Class"
                )
            ]
        )

        let dubaiTrip = Trip(
            name: "Dubai Luxury Retreat",
            destination: "Dubai, UAE",
            startDate: date(addingDays: 21),
            endDate: date(addingDays: 26),
            items: [
                ItineraryItem(
                    title: "Flight — EK201 JFK → DXB",
                    type: .flight,
                    startDate: date(addingDays: 21, hours: 22),
                    endDate: date(addingDays: 22, hours: 18),
                    location: "JFK → DXB",
                    notes: "First Class Suite · Gate B2 · Emirates A380"
                ),
                ItineraryItem(
                    title: "Check-in — Burj Al Arab",
                    type: .hotel,
                    startDate: date(addingDays: 22, hours: 15),
                    endDate: date(addingDays: 26, hours: 12),
                    location: "Jumeirah St, Dubai",
                    notes: "Royal Suite — private butler included"
                ),
                ItineraryItem(
                    title: "Desert Safari & Private Dinner",
                    type: .activity,
                    startDate: date(addingDays: 23, hours: 16),
                    location: "Dubai Desert Conservation Reserve",
                    notes: "Private camp · 6 guests · Camel ride included"
                ),
                ItineraryItem(
                    title: "Helicopter Tour — Palm Jumeirah",
                    type: .activity,
                    startDate: date(addingDays: 24, hours: 10),
                    location: "Dubai Helipad, Downtown",
                    notes: "30-min tour · 4 seats reserved"
                )
            ]
        )

        if let data = try? encoder.encode([tokyoTrip, dubaiTrip]) {
            UserDefaults.standard.set(data, forKey: "jetsetter_trips")
        }

        // ── Expenses ──────────────────────────────────────────────────────────

        let expenses: [Expense] = [
            Expense(amount: 4_200, currency: "USD", category: .accommodation,
                    merchant: "Park Hyatt Tokyo",
                    date: date(addingDays: -2),
                    notes: "6 nights — Tokyo Business Summit"),
            Expense(amount: 280, currency: "USD", category: .food,
                    merchant: "Nobu Tokyo",
                    date: date(addingDays: -1),
                    notes: "Business dinner × 3 guests"),
            Expense(amount: 640, currency: "USD", category: .transport,
                    merchant: "Narita Express + Uber Black",
                    date: date(addingDays: -3)),
            Expense(amount: 1_180, currency: "USD", category: .business,
                    merchant: "Global Innovators Summit",
                    date: date(addingDays: -5),
                    notes: "Conference registration + materials"),
            Expense(amount: 320, currency: "USD", category: .shopping,
                    merchant: "Isetan Department Store",
                    date: date(addingDays: -2),
                    notes: "Client gifts"),
            Expense(amount: 40.20, currency: "USD", category: .mileage,
                    merchant: "Airport — Hotel",
                    date: now,
                    mileageDistance: 60.0),
            Expense(amount: 95, currency: "USD", category: .entertainment,
                    merchant: "TeamLab Planets",
                    date: date(addingDays: -4))
        ]

        if let data = try? encoder.encode(expenses) {
            UserDefaults.standard.set(data, forKey: "jetsetter_expenses")
        }

        // ── Bags ──────────────────────────────────────────────────────────────

        let bags: [Bag] = [
            Bag(
                nickname: "Rimowa Original",
                description: "Silver aluminum hard-shell — large",
                airline: "American Airlines",
                flightNumber: "AA169",
                bagTagNumber: "0012345678",
                hasAirTag: true,
                status: .inTransit,
                lastLocation: "JFK Baggage Handling — Terminal 8",
                lastChecked: cal.date(byAdding: .minute, value: -12, to: now)
            ),
            Bag(
                nickname: "Tumi Alpha — Carry-On",
                description: "Black carry-on, Tumi Alpha 3",
                hasAirTag: true,
                status: .delivered,
                lastLocation: "Park Hyatt Tokyo — Concierge",
                lastChecked: cal.date(byAdding: .hour, value: -1, to: now)
            ),
            Bag(
                nickname: "Brioni Suit Carrier",
                description: "Navy garment bag — Brioni",
                airline: "American Airlines",
                flightNumber: "AA169",
                bagTagNumber: "0012345679",
                hasAirTag: false,
                status: .atCarousel,
                lastLocation: "NRT — Carousel 4",
                lastChecked: cal.date(byAdding: .minute, value: -5, to: now)
            )
        ]

        if let data = try? encoder.encode(bags) {
            UserDefaults.standard.set(data, forKey: "jetsetter_bags")
        }

        UserDefaults.standard.set(true, forKey: populatedKey)
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

        if lower.contains("flight") || lower.contains("aa100") || lower.contains("delay") || lower.contains("gate") {
            return """
            Your **AA100** (JFK → LHR) is currently **on time** and 65% complete — cruising at 35,000 ft over the North Atlantic.

            Estimated arrival at Heathrow Terminal 3 is on schedule. Departing from Gate B22, arriving Gate B44. Baggage claim carousel 7.

            Would you like me to set a gate reminder or check your lounge access at Heathrow?
            """
        }

        if lower.contains("hotel") || lower.contains("check in") || lower.contains("room") || lower.contains("stay") {
            return """
            For your **Tokyo Business Summit** stay, here are the top available properties:

            - **Four Seasons Tokyo** — from $785/night · ⭐ 4.95
            - **The Peninsula Tokyo** — from $710/night · ⭐ 4.90
            - **Park Hyatt Tokyo** — from $420/night · ⭐ 4.85

            All properties offer complimentary airport transfers for suite bookings. Shall I add one to your itinerary?
            """
        }

        if lower.contains("ride") || lower.contains("uber") || lower.contains("lyft") || lower.contains("transport") || lower.contains("car service") {
            return """
            I've found rides near your current location:

            - **Uber Black** — 4 min away · $38–$46
            - **Lyft Lux Black** — 5 min away · $41–$52
            - **Uber Black SUV** — 7 min away · $52–$68

            No surge pricing on Uber Black right now. Tap any option in the Ground Transport tab to book directly.
            """
        }

        if lower.contains("expense") || lower.contains("budget") || lower.contains("spend") || lower.contains("cost") {
            return """
            Your **Tokyo Business Summit** travel expenses to date:

            | Category | Amount |
            |---|---|
            | Accommodation | $4,200 |
            | Business | $1,180 |
            | Transportation | $640 |
            | Food & Dining | $280 |
            | Shopping | $320 |
            | Entertainment | $95 |
            | **Total** | **$6,715** |

            You're within your estimated $8,000 travel budget. A mileage reimbursement of $40.20 is pending.
            """
        }

        if lower.contains("luggage") || lower.contains("bag") || lower.contains("baggage") || lower.contains("suitcase") {
            return """
            Current **luggage status** for your trip:

            🧳 **Rimowa Original** — In Transit · JFK Baggage Handling T8 · 12 min ago
            👜 **Tumi Carry-On** — Delivered · Park Hyatt Tokyo Concierge · 1 hr ago
            👔 **Brioni Suit Carrier** — At Carousel 4 · NRT Airport · 5 min ago

            AirTag-equipped bags are tracking normally. Your Rimowa is expected at NRT Carousel 4 in approximately 35 minutes.
            """
        }

        if lower.contains("itinerary") || lower.contains("schedule") || lower.contains("plan") || lower.contains("trip") {
            return """
            Your **Tokyo Business Summit** itinerary (next 7 days):

            **Day 1** — AA169 JFK → NRT · 11:45 PM · Gate B22 · Seat 3A · Business Class
            **Day 2** — Arrival NRT · Check-in Park Hyatt Tokyo · 3:00 PM
            **Day 3–5** — Global Innovators Summit · Tokyo International Forum
            **Day 4** — Sukiyabashi Jiro dinner reservation · 8:00 PM · 4 guests
            **Day 7** — Check-out · AA170 NRT → JFK · 6:00 PM · Gate C14

            Coming up: **Dubai Luxury Retreat** starts in 21 days. Review that itinerary?
            """
        }

        if lower.contains("lounge") || lower.contains("admirals") || lower.contains("centurion") {
            return """
            With your **Admirals Club** and **Centurion** memberships, you have access to:

            **JFK Terminal 8:**
            - Admirals Club (open 5:00 AM – last departure)
            - Centurion Lounge (Level 4 — opens 5:30 AM)

            **LHR Terminal 3:**
            - British Airways Galleries Club (reciprocal AA status)

            Shall I add lounge access details to your pre-departure checklist?
            """
        }

        if lower.contains("weather") || lower.contains("forecast") || lower.contains("temperature") {
            return """
            **Tokyo weather forecast** for your visit:

            - **Days 1–3:** Partly cloudy · 18°C (64°F) · Low rain chance
            - **Days 4–5:** Clear skies · 20°C (68°F) · Ideal for outdoor dinners
            - **Days 6–7:** Light rain expected in evenings

            I'd recommend packing a compact travel umbrella. Want me to add a packing reminder?
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
}
