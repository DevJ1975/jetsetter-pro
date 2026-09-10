// File: Core/Services/Demo/DemoDataSeeder.swift
//
// Builds the demo dataset: one business trip from Las Vegas to Atlanta on
// Delta DL1423, with a boarding pass, checked bags mid-load at LAS, a hotel,
// a rental car, an event ticket, insurance and matching expenses.
//
// COMPILED ONLY INTO Debug AND Beta (see DemoMode.swift). Not in Release.
//
// Two deliberate choices:
//
// 1. Times are relative to `now`, not the fixed July 2026 dates the previous
//    seeder used. Departure lands 75 minutes out, which is the most interesting
//    state in the whole app: the check-in window is open, the gate-closing
//    marker is live, the bags are being loaded, and the countdown moves while
//    you present.
//
// 2. Weather is NOT seeded. The destination is a real city string, so Home
//    fetches genuine current conditions for Atlanta through WeatherService.
//    A demo that shows made-up weather teaches the audience nothing about the
//    product; this one shows the real integration working.

#if DEMO_ENABLED

import Foundation

enum DemoDataSeeder {

    // The persona, kept from the original demo so returning viewers recognise it.
    static let passengerName = "Jordan Ellis"
    static let homeAirport = "LAS"
    static let flightNumber = "DL1423"
    static let returnFlightNumber = "DL1876"
    static let origin = "LAS"
    static let destination = "ATL"
    static let gate = "C22"
    static let terminal = "1"
    static let seat = "3A"
    static let cabin = "First"
    static let recordLocator = "JX7QF2"
    static let hotelConfirmation = "RC-8842193"

    /// Minutes from now to departure. Chosen so the check-in window (24h), the
    /// gate-closing marker (90m) and the bag-loading window are all live.
    static let minutesToDeparture = 75

    /// Block time LAS → ATL. Dates are absolute instants, so this is air time
    /// plus taxi, not the three-hour clock change.
    static let blockSeconds: TimeInterval = 4 * 3600 + 5 * 60

    // MARK: - Seed

    @MainActor
    static func seed(now: Date = Date()) async -> DemoSeedLedger {
        var ledger = DemoSeedLedger()
        let calendar = Calendar.current

        let departure = calendar.date(byAdding: .minute, value: minutesToDeparture, to: now) ?? now
        let arrival = departure.addingTimeInterval(blockSeconds)
        let tripStart = calendar.startOfDay(for: now)
        let tripEnd = calendar.date(byAdding: .day, value: 3, to: tripStart) ?? tripStart
        let returnDeparture = calendar.date(byAdding: .hour, value: 15, to: tripEnd) ?? tripEnd

        // ── Trip ──────────────────────────────────────────────────────────────
        // Destination is a real place string so Home's weather lookup resolves
        // Atlanta and shows live conditions.
        let trip = Trip(
            name: "Atlanta Board Meeting",
            destination: "Atlanta, GA",
            startDate: tripStart,
            endDate: returnDeparture,
            items: [
                ItineraryItem(
                    title: "Delta \(flightNumber)",
                    type: .flight,
                    startDate: departure,
                    endDate: arrival,
                    location: "\(origin) → \(destination)",
                    notes: "Gate \(gate) · Terminal \(terminal) · Seat \(seat) · \(cabin) Class",
                    confirmationNumber: recordLocator,
                    bookingProvider: "Delta Air Lines",
                    cost: BookingCost(amount: 1_290.00, currencyCode: "USD"),
                    flightDetails: FlightBookingDetails(
                        airline: "Delta Air Lines",
                        flightNumber: "DL 1423",
                        originCode: origin,
                        destinationCode: destination,
                        seat: seat,
                        cabinClass: cabin,
                        terminal: terminal,
                        gate: gate
                    )
                ),
                ItineraryItem(
                    title: "The Ritz-Carlton, Atlanta",
                    type: .hotel,
                    startDate: arrival.addingTimeInterval(90 * 60),
                    endDate: calendar.date(byAdding: .hour, value: 11, to: tripEnd) ?? tripEnd,
                    location: "181 Peachtree St NE, Atlanta, GA",
                    notes: "Executive Suite · Confirmation \(hotelConfirmation)",
                    confirmationNumber: hotelConfirmation,
                    bookingProvider: "Marriott",
                    cost: BookingCost(amount: 412.55, currencyCode: "USD"),
                    hotelDetails: HotelBookingDetails(
                        address: "181 Peachtree St NE, Atlanta, GA 30303",
                        roomType: "Executive Suite",
                        phone: "+1 404-659-0400"
                    )
                ),
                ItineraryItem(
                    title: "Hertz — ATL pickup",
                    type: .transport,
                    startDate: arrival.addingTimeInterval(45 * 60),
                    endDate: returnDeparture.addingTimeInterval(-2 * 3600),
                    location: "Hartsfield-Jackson Rental Car Center",
                    notes: "Confirmation HZ-4471-ATL",
                    confirmationNumber: "HZ-4471-ATL",
                    bookingProvider: "Hertz",
                    cost: BookingCost(amount: 268.40, currencyCode: "USD"),
                    carDetails: CarRentalDetails(
                        vehicleClass: "Premium",
                        vehicleDescription: "Tesla Model 3 or similar",
                        pickupLocation: "ATL Rental Car Center",
                        dropoffLocation: "ATL Rental Car Center"
                    )
                ),
                ItineraryItem(
                    title: "Q3 Board Meeting",
                    type: .activity,
                    startDate: calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tripStart) ?? tripStart) ?? tripStart,
                    endDate: calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tripStart) ?? tripStart),
                    location: "Atlanta HQ — Executive Boardroom",
                    notes: "Q3 leadership review · full-day session"
                ),
                ItineraryItem(
                    title: "Dinner — Bacchanalia",
                    type: .restaurant,
                    startDate: calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tripStart) ?? tripStart) ?? tripStart,
                    location: "1460 Ellsworth Industrial Blvd NW, Atlanta",
                    notes: "Tasting menu · client dinner"
                ),
                ItineraryItem(
                    title: "Delta \(returnFlightNumber)",
                    type: .flight,
                    startDate: returnDeparture,
                    endDate: returnDeparture.addingTimeInterval(5 * 3600 + 10 * 60),
                    location: "\(destination) → \(origin)",
                    notes: "Seat \(seat) · \(cabin) Class",
                    confirmationNumber: recordLocator,
                    bookingProvider: "Delta Air Lines",
                    flightDetails: FlightBookingDetails(
                        airline: "Delta Air Lines",
                        flightNumber: "DL 1876",
                        originCode: destination,
                        destinationCode: origin,
                        seat: seat,
                        cabinClass: cabin,
                        terminal: nil,
                        gate: nil
                    )
                )
            ]
        )
        TravelStore.appendTrip(trip)
        ledger.tripIDs = [trip.id]
        ledger.seededFlights = [
            DemoSeedLedger.SeededFlight(flightNumber: flightNumber, departure: departure),
            DemoSeedLedger.SeededFlight(flightNumber: returnFlightNumber, departure: returnDeparture)
        ]

        // ── Wallet: the tickets ───────────────────────────────────────────────
        let walletItems = walletItems(tripID: trip.id, departure: departure, arrival: arrival, tripEnd: tripEnd)
        var stored: [WalletItem] = CodableDefaults.load([WalletItem].self, forKey: walletKey) ?? []
        stored.append(contentsOf: walletItems)
        stored.sort { $0.date < $1.date }
        try? CodableDefaults.save(stored, forKey: walletKey)
        // The wallet lives in two stores. Writing only the view-model cache lets
        // a later load from LocalDataService overwrite the seeded items away.
        // Awaited, not fired-and-forgotten, so the mirror is in place before the
        // wallet screen can read it.
        for item in walletItems { await LocalDataService.shared.upsertWalletItem(item) }
        ledger.walletItemIDs = walletItems.map(\.id)

        // ── Bags, mid-load at LAS ─────────────────────────────────────────────
        let bags = bags(now: now)
        BagStore.save(BagStore.load() + bags)
        ledger.bagIDs = bags.map(\.id)
        // The luggage screen only reloads on this notification, and nothing else
        // in the app posts it.
        NotificationCenter.default.post(name: .jetSetterBagsActivated, object: nil)

        // ── Expenses ──────────────────────────────────────────────────────────
        let expenses = expenses(now: now)
        for expense in expenses { TravelStore.appendExpense(expense) }
        ledger.expenseIDs = expenses.map(\.id)

        // ── Profile, only where blank ─────────────────────────────────────────
        let prefs = UserPreferences.shared
        if prefs.displayName.isEmpty {
            prefs.displayName = passengerName
            ledger.filledDisplayName = passengerName
        }
        if prefs.homeAirport.isEmpty {
            prefs.homeAirport = homeAirport
            ledger.filledHomeAirport = homeAirport
        }
        if !prefs.hasCompletedOnboarding {
            prefs.hasCompletedOnboarding = true
            ledger.completedOnboarding = true
        }

        // ── Live Activity for the boarding flight ─────────────────────────────
        FlightLiveActivityService.shared.start(
            flightNumber: flightNumber,
            airline: "Delta Air Lines",
            originIATA: origin,
            destinationIATA: destination,
            scheduledDeparture: departure,
            gate: gate,
            terminal: terminal,
            // Boarding has not started 75 minutes out; the flight is simply on time.
            initialStatus: .onTime,
            scheduledArrival: arrival
        )
        ledger.startedLiveActivity = true

        return ledger
    }

    private static let walletKey = "jetsetter_wallet_items"

    // MARK: - Wallet items

    @MainActor
    private static func walletItems(tripID: UUID, departure: Date, arrival: Date, tripEnd: Date) -> [WalletItem] {
        let endDateString = ISO8601Formatters.internetDateTime.string(from: tripEnd)

        let boardingPass = WalletItem(
            tripId: tripID,
            itemType: .boardingPass,
            title: "DL 1423 · \(origin) → \(destination)",
            confirmationNumber: recordLocator,
            date: departure,
            rawData: [
                "airline": "Delta Air Lines",
                "flight_number": flightNumber,
                "iata_code": "DL",
                "departure_airport": origin,
                "arrival_airport": destination,
                "seat_number": seat,
                "cabin_class": cabin,
                "gate": gate,
                "terminal": terminal,
                "boarding_group": "1",
                "sequence_number": "42",
                // A real IATA BCBP payload, so the pass renders a scannable QR
                // instead of the grey placeholder.
                "barcode_message": boardingPassBarcode(departure: departure),
                "source": "demo"
            ]
        )

        let hotel = WalletItem(
            tripId: tripID,
            itemType: .hotelReservation,
            title: "The Ritz-Carlton, Atlanta",
            confirmationNumber: hotelConfirmation,
            date: arrival.addingTimeInterval(90 * 60),
            rawData: [
                "hotel_address": "181 Peachtree St NE, Atlanta, GA 30303",
                "check_in_date": ISO8601Formatters.internetDateTime.string(from: arrival.addingTimeInterval(90 * 60)),
                "check_out_date": endDateString,
                "contact_email": "reservations.atlanta@ritzcarlton.com",
                "end_date": endDateString,
                "source": "demo"
            ]
        )

        let car = WalletItem(
            tripId: tripID,
            itemType: .carRental,
            title: "Hertz — ATL pickup",
            confirmationNumber: "HZ-4471-ATL",
            date: arrival.addingTimeInterval(45 * 60),
            rawData: [
                "rental_company": "Hertz",
                "vehicle_class": "Premium",
                "pickup_location": "ATL Rental Car Center",
                "end_date": endDateString,
                "source": "demo"
            ]
        )

        let ticket = WalletItem(
            tripId: tripID,
            itemType: .eventTicket,
            title: "Q3 Leadership Summit",
            confirmationNumber: "QLS-2026-0714",
            date: arrival.addingTimeInterval(20 * 3600),
            rawData: [
                "venue": "Atlanta HQ — Executive Boardroom",
                "event_location": "3344 Peachtree Rd NE, Atlanta, GA",
                "source": "demo"
            ]
        )

        let insurance = WalletItem(
            tripId: tripID,
            itemType: .travelInsurance,
            title: "AIG Travel Guard — Deluxe",
            confirmationNumber: "TG-9128340-IK",
            date: departure.addingTimeInterval(-72 * 3600),
            rawData: [
                "policy_number": "TG-9128340-IK",
                "provider": "AIG Travel Guard",
                "coverage_type": "Deluxe — Single Trip",
                "contact_email": "claims@travelguard.com",
                "end_date": endDateString,
                "source": "demo"
            ]
        )

        return [insurance, boardingPass, hotel, car, ticket]
    }

    /// Builds a valid IATA BCBP (Resolution 792) mandatory-section payload for
    /// the demo pass, using the exact field offsets `BCBPParser` reads back.
    static func boardingPassBarcode(departure: Date) -> String {
        func padRight(_ value: String, _ width: Int) -> String {
            let clipped = String(value.prefix(width))
            return clipped + String(repeating: " ", count: max(0, width - clipped.count))
        }
        func padLeft(_ value: String, _ width: Int) -> String {
            let clipped = String(value.suffix(width))
            return String(repeating: "0", count: max(0, width - clipped.count)) + clipped
        }
        let julian = Calendar.current.ordinality(of: .day, in: .year, for: departure) ?? 1

        var payload = "M1"                              // format + one leg
        payload += padRight("ELLIS/JORDAN", 20)         // 2..<22  passenger
        payload += "E"                                  // 22      electronic ticket
        payload += padRight(recordLocator, 7)           // 23..<30 record locator
        payload += padRight(origin, 3)                  // 30..<33
        payload += padRight(destination, 3)             // 33..<36
        payload += padRight("DL", 3)                    // 36..<39 carrier
        payload += padRight("1423", 5)                  // 39..<44 flight
        payload += padLeft(String(julian), 3)           // 44..<47 day of year
        payload += "F"                                  // 47      compartment
        payload += padLeft(seat, 4)                     // 48..<52 seat
        payload += "0042 100"                           //         sequence + status
        return payload
    }

    // MARK: - Bags

    /// Four checked bags spread across the LAS ground pipeline, so the tracker
    /// shows the whole journey at once: one still on the sort belt, one being
    /// loaded at the gate, one already secured in the hold, one just tagged.
    private static func bags(now: Date) -> [Bag] {
        func minutesAgo(_ minutes: Int) -> Date {
            Calendar.current.date(byAdding: .minute, value: -minutes, to: now) ?? now
        }

        let counter = "LAS Terminal \(terminal) — Delta counter"
        let sortBelt = "LAS Belt 4 — outbound sort"
        let loader = "LAS Gate \(gate) — loader"
        let hold = "DL1423 — cargo hold 2"

        let secured = Bag(
            nickname: "Rimowa Check-In L",
            description: "Silver aluminium hard-shell — large",
            airline: "Delta Air Lines",
            flightNumber: flightNumber,
            bagTagNumber: "0012345678",
            hasAirTag: true,
            status: .onAircraft,
            lastLocation: hold,
            lastChecked: minutesAgo(4),
            scanHistory: [
                BagScanEvent(timestamp: minutesAgo(68), location: counter, scanType: .checkIn, note: "Priority tag applied"),
                BagScanEvent(timestamp: minutesAgo(54), location: sortBelt, scanType: .onBelt),
                BagScanEvent(timestamp: minutesAgo(19), location: loader, scanType: .loaderTransfer),
                BagScanEvent(timestamp: minutesAgo(4), location: hold, scanType: .securedInCargo, note: "Secured for departure")
            ]
        )

        let loading = Bag(
            nickname: "Tumi Alpha 3 — Large",
            description: "Black ballistic nylon, expandable",
            airline: "Delta Air Lines",
            flightNumber: flightNumber,
            bagTagNumber: "0012345679",
            hasAirTag: true,
            status: .loading,
            lastLocation: loader,
            lastChecked: minutesAgo(2),
            scanHistory: [
                BagScanEvent(timestamp: minutesAgo(66), location: counter, scanType: .checkIn),
                BagScanEvent(timestamp: minutesAgo(51), location: sortBelt, scanType: .onBelt),
                BagScanEvent(timestamp: minutesAgo(2), location: loader, scanType: .loaderTransfer, note: "Loading onto the aircraft now")
            ]
        )

        let onBelt = Bag(
            nickname: "Brioni Suit Carrier",
            description: "Navy garment bag",
            airline: "Delta Air Lines",
            flightNumber: flightNumber,
            bagTagNumber: "0012345680",
            hasAirTag: false,
            status: .onBelt,
            lastLocation: sortBelt,
            lastChecked: minutesAgo(6),
            scanHistory: [
                BagScanEvent(timestamp: minutesAgo(64), location: counter, scanType: .checkIn),
                BagScanEvent(timestamp: minutesAgo(6), location: sortBelt, scanType: .onBelt, note: "Moving through the sort facility")
            ]
        )

        let tagged = Bag(
            nickname: "Away Weekender",
            description: "Tan leather weekender",
            airline: "Delta Air Lines",
            flightNumber: flightNumber,
            bagTagNumber: "0012345681",
            hasAirTag: true,
            status: .checkedIn,
            lastLocation: counter,
            lastChecked: minutesAgo(61),
            scanHistory: [
                BagScanEvent(timestamp: minutesAgo(61), location: counter, scanType: .checkIn)
            ]
        )

        return [loading, secured, onBelt, tagged]
    }

    // MARK: - Expenses

    private static func expenses(now: Date) -> [Expense] {
        func daysAgo(_ days: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        }
        return [
            Expense(amount: 1_290.00, currency: "USD", category: .transport,
                    merchant: "Delta Air Lines", date: daysAgo(12), notes: "DL 1423 / DL 1876 · First"),
            Expense(amount: 412.55, currency: "USD", category: .accommodation,
                    merchant: "The Ritz-Carlton", date: daysAgo(12), notes: "Executive Suite · 3 nights"),
            Expense(amount: 268.40, currency: "USD", category: .transport,
                    merchant: "Hertz", date: daysAgo(9), notes: "Premium · ATL Rental Car Center"),
            Expense(amount: 24.00, currency: "USD", category: .transport,
                    merchant: "Uber", date: Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now,
                    notes: "Home to LAS")
        ]
    }
}

#endif
