package com.jetsetter.pro.core.data.mock

import com.jetsetter.pro.core.model.Airport
import com.jetsetter.pro.core.model.Expense
import com.jetsetter.pro.core.model.ExpenseCategory
import com.jetsetter.pro.core.model.Flight
import com.jetsetter.pro.core.model.ItineraryItem
import com.jetsetter.pro.core.model.ItineraryItemType
import com.jetsetter.pro.core.model.PackingItem
import com.jetsetter.pro.core.model.Trip

/**
 * Seed / demo data — the Android counterpart of the iOS `MockDataService`. Lets the app
 * be fully usable with no API keys configured.
 */
object MockData {

    val nextFlight = Flight(
        ident = "DL1423",
        operatorName = "Delta Air Lines",
        origin = Airport("LAS", "Las Vegas", "Harry Reid Intl"),
        destination = Airport("ATL", "Atlanta", "Hartsfield–Jackson"),
        status = "On Time",
        scheduledOut = "2026-07-14T07:00:00Z",
        scheduledIn = "2026-07-14T14:05:00Z",
        gateOrigin = "C22",
        terminalOrigin = "3",
        progressPercent = 0,
    )

    val trips = listOf(
        Trip(
            id = "trip-atl-2026",
            name = "Atlanta Board Meeting",
            destination = "Atlanta, GA",
            startDate = "2026-07-14",
            endDate = "2026-07-17",
            items = listOf(
                ItineraryItem(
                    title = "DL 1423 · LAS → ATL",
                    type = ItineraryItemType.FLIGHT,
                    startDate = "2026-07-14T07:00:00Z",
                    location = "Harry Reid Intl (LAS)",
                ),
                ItineraryItem(
                    title = "The Ritz-Carlton, Atlanta",
                    type = ItineraryItemType.HOTEL,
                    startDate = "2026-07-14T15:00:00Z",
                    location = "181 Peachtree St NE",
                ),
                ItineraryItem(
                    title = "Board Dinner — Bacchanalia",
                    type = ItineraryItemType.RESTAURANT,
                    startDate = "2026-07-15T19:30:00Z",
                    location = "1460 Ellsworth Industrial Blvd",
                ),
            ),
            packingList = listOf(
                PackingItem(name = "Passport", isPacked = true),
                PackingItem(name = "Laptop + charger"),
                PackingItem(name = "Board deck (printed)"),
                PackingItem(name = "Suit"),
            ),
        ),
        Trip(
            id = "trip-tyo-2026",
            name = "Tokyo Product Summit",
            destination = "Tokyo, Japan",
            startDate = "2026-09-02",
            endDate = "2026-09-09",
            items = listOf(
                ItineraryItem(
                    title = "JL 5 · LAX → HND",
                    type = ItineraryItemType.FLIGHT,
                    startDate = "2026-09-02T11:45:00Z",
                    location = "Tom Bradley Intl (LAX)",
                ),
                ItineraryItem(
                    title = "Park Hyatt Tokyo",
                    type = ItineraryItemType.HOTEL,
                    startDate = "2026-09-03T15:00:00Z",
                    location = "Shinjuku",
                ),
            ),
            packingList = listOf(
                PackingItem(name = "JR Pass voucher"),
                PackingItem(name = "Pocket Wi-Fi"),
                PackingItem(name = "Power adapter (Type A)"),
            ),
        ),
    )

    val expenses = listOf(
        Expense(amount = 412.55, category = ExpenseCategory.ACCOMMODATION, merchant = "The Ritz-Carlton", date = "2026-07-14"),
        Expense(amount = 86.20, category = ExpenseCategory.FOOD, merchant = "Bacchanalia", date = "2026-07-15"),
        Expense(amount = 24.00, category = ExpenseCategory.TRANSPORT, merchant = "Uber", date = "2026-07-14"),
        Expense(amount = 1290.00, category = ExpenseCategory.BUSINESS, merchant = "Delta Air Lines", date = "2026-07-10"),
    )
}
