// File: Core/Services/IRIS/IRISCapabilities.swift
//
// A human-readable catalog of what IRIS can actually DO. Every entry here
// corresponds to a real tool she can call (backed by a live app service or API).
//
// NOTE: this list is no longer injected verbatim into the system prompt — the
// on-device model's ~4K-token window can't afford duplicating what the tools'
// own names and descriptions already convey, so IRISPersonality was trimmed to a
// short summary and relies on the registered tool schemas. This file remains the
// developer-facing reference (and `capabilitiesSection()`/`actionsSection()` are
// kept for docs/tests). Keep it in sync with the tools registered in
// IRISAgentService so it stays an honest description of her abilities.

import Foundation

enum IRISCapabilities {

    /// One thing IRIS can do, phrased as a prompt line.
    struct Capability {
        /// The tool that backs this capability (documentation only).
        let tool: String
        /// Human-readable line injected into the system prompt.
        let line: String
    }

    // MARK: - Lookups (read-only; run immediately, no confirmation)

    /// Real-data lookups. IRIS should prefer these over her training.
    static let lookups: [Capability] = [
        Capability(tool: "getUserTrips",
                   line: "Read the user's real trips, itinerary items, flights and hotels."),
        Capability(tool: "getWeather",
                   line: "Live weather (temp, conditions, wind) for any city or IATA code."),
        Capability(tool: "getVisaAndCountryEssentials",
                   line: "US-passport visa rules plus emergency numbers, tipping, plug types and water safety."),
        Capability(tool: "getLearnedTravelProfile",
                   line: "What the app has learned about this traveler — typical seat, airlines, cabin, hotels, spend."),
        Capability(tool: "get_departure_briefing",
                   line: "When to leave for the airport, fusing live traffic, TSA-wait and weather."),
        Capability(tool: "getFlightStatus",
                   line: "Live flight status by flight number (FlightAware): gate, terminal, delay, cancellation."),
        Capability(tool: "convertCurrency",
                   line: "Convert money between currencies at live FX rates (e.g. €200 in USD)."),
        Capability(tool: "searchRentalCars",
                   line: "Search rental cars across Enterprise, Hertz and National for a location and dates."),
        Capability(tool: "checkDisruption",
                   line: "During a delay/cancellation, find alternative flights on the route and check rebooking eligibility."),
        Capability(tool: "traceBaggage",
                   line: "Trace a checked bag by its tag number via SITA WorldTracer."),
        Capability(tool: "flightActions",
                   line: "Report where the user's checked bags are and the ETA to the carousel after landing.")
    ]

    // MARK: - Actions (drive the app)

    /// Things IRIS can perform. Navigation and look-ups run immediately;
    /// everything that writes or sends is STAGED for user confirmation.
    static let actions: [Capability] = [
        Capability(tool: "navigate",
                   line: "Navigate to any screen (Home, Itinerary, Expenses, Check-In, Flight Tracker, Documents, Packing List, Ground Transport, Currency), or open the Flight Tracker with live status for a flight number. Runs immediately."),
        Capability(tool: "flightActions",
                   line: "Text the user's saved loved ones on takeoff/landing (opens a pre-filled message they send)."),
        Capability(tool: "rememberUserPreference",
                   line: "Remember a stated preference (diet, seat, hotel style…) for future conversations."),
        Capability(tool: "logExpense",
                   line: "[confirm] Prepare a travel expense to log."),
        Capability(tool: "addTrip",
                   line: "[confirm] Prepare a new trip for the itinerary."),
        Capability(tool: "checkInForFlight",
                   line: "[confirm] Prepare check-in for the next upcoming flight."),
        Capability(tool: "generatePackingList",
                   line: "[confirm] Prepare a smart packing list for a trip."),
        Capability(tool: "submitExpenses",
                   line: "[confirm] Prepare to submit logged expenses to a connected provider (email, Expensify, Ramp, Brex, Divvy)."),
        Capability(tool: "addToCalendar",
                   line: "[confirm] Prepare to add a trip's flights and events to the device Calendar.")
    ]

    // MARK: - Prompt section builders

    /// The CAPABILITIES block for IRIS's system prompt.
    static func capabilitiesSection() -> String {
        let bullets = lookups.map { "• \($0.line)" }.joined(separator: "\n")
        return """
        When tools are available to you, prefer real data over your training:
        \(bullets)
        """
    }

    /// The ACTIONS block for IRIS's system prompt.
    static func actionsSection() -> String {
        let bullets = actions.map { "• \($0.line)" }.joined(separator: "\n")
        return """
        You are not just an advisor — you can operate JetSetter Pro for the user.
        Lines marked [confirm] are STAGED, not done (see the confirmation rule):
        \(bullets)
        """
    }
}
