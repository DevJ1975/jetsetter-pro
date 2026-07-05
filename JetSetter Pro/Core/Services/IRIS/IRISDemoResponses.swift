// File: Core/Services/IRIS/IRISDemoResponses.swift
//
// Pre-written IRIS-voice responses keyed to common demo questions. Used as a
// fallback when Apple Intelligence is unavailable on the simulator so the
// demo always shows great answers in IRIS's anticipatory, warm voice.

import Foundation

enum IRISDemoResponses {

    /// Returns an IRIS-personality response that matches the prompt's intent.
    /// Falls back to a general welcome response when no keywords match.
    static func response(for prompt: String) -> String {
        let lower = prompt.lowercased()

        // Identity / introduction
        if matches(lower, any: ["who are you", "your name", "what's iris", "what is iris"]) {
            return """
            I'm IRIS — your Intelligent Routing & Itinerary Specialist. Think of me as a quietly relentless travel agent who's already read every detail of your trip. I pull weather, visa rules, ride times and currency rates in real time, and I remember how you like to travel. Just ask.
            """
        }

        // Weather — rendered from the live departure briefing so it can't
        // contradict the Departure Optimizer (§7.3).
        if matches(lower, any: ["weather", "rain", "forecast", "umbrella"]) {
            let b = DepartureBriefing.current()
            return """
            Departure conditions at **\(b.originIATA)** are looking good — **\(b.weatherLabel.lowercased()) and \(b.temperatureF)°F**, light winds for your 7:00 AM push. I'm keeping an eye on Atlanta, where afternoon storms are possible and could nudge \(b.flightNumber)'s arrival.

            Want me to set a weather alert for your departure day?
            """
        }

        // Departure / leave / traffic — rendered from the live briefing (§7.3).
        if matches(lower, any: ["leave", "depart", "when should i", "navigate", "drive", "uber", "lyft", "traffic"]) {
            let b = DepartureBriefing.current()
            return """
            For **\(b.flightNumber)** I'd \(b.summary). That keeps a comfortable cushion before boarding.

            Want me to open in-app navigation, or set a 15-minute leave-by alert?
            """
        }

        // Expenses / submit
        if matches(lower, any: ["expense", "submit", "report", "approver", "ramp", "concur"]) {
            return """
            I can send your **Atlanta Board Meeting** report straight to one of your connected providers (Expensify, Ramp, Brex, BILL) or as a polished PDF to your approver. Four items so far, total **$1,812.75** — all categorized.

            One tap — should I queue it up?
            """
        }

        // Packing
        if matches(lower, any: ["pack", "packing", "what to bring", "luggage list"]) {
            return """
            For a two-night board meeting in Atlanta, I'd plan around:

            • 2 suits (navy + charcoal), neutral dress shoes
            • Board deck + laptop and charger
            • A light layer — ATL runs warm and humid, mid-80s°F
            • Wallet passes saved offline (DL 1423 + Ritz-Carlton)

            Want me to build the full list?
            """
        }

        // Hotel
        if matches(lower, any: ["hotel", "stay", "room", "ritz", "booking"]) {
            return """
            You're booked at **The Ritz-Carlton, Atlanta** (Executive Suite) for Jul 14–17 — confirmation **RC-8842193**.

            Want me to email the concierge ahead about a late arrival and your **8:00 PM dinner at Bacchanalia** on the 15th?
            """
        }

        // Flight status
        if matches(lower, any: ["flight", "dl 1423", "dl1423", "delay", "gate", "status"]) {
            return """
            Your **DL 1423 (LAS → ATL)** departs **7:00 AM**, gate **C22** — Seat 3A, First.

            Heads up: I'm tracking a possible weather hold at ATL that could push departure to 8:35 AM. If it firms up, I've already lined up 3 same-day alternatives. Want to review them?
            """
        }

        // Disruption
        if matches(lower, any: ["disruption", "cancelled", "rebook", "alternative", "missed connection"]) {
            return """
            Good thinking. **DL 1423** has a weather hold at ATL — departure slips 7:00 → 8:35 AM. I've already done the work:

            • **AA 218** — First, arrives 3:25 PM · $412 · 5 seats
            • **DL 2207** — Comfort+, arrives 4:58 PM · $289 · 9 seats
            • **WN 1190** — Main, arrives 6:40 PM · $198 · 14 seats

            I'd nudge you toward **AA 218** — keeps you in First and lands earliest. Should I open the rebooking?
            """
        }

        // Currency
        if matches(lower, any: ["currency", "exchange", "convert", "usd"]) {
            return """
            Atlanta's a domestic trip, so no conversion needed — everything's in **USD**. Your board-meeting spend so far is **$1,812.75** across 4 items, with the Delta airfare as the biggest line.

            For the Tokyo Product Summit in September I'll switch on live JPY tracking. Want me to flag rate changes closer to that trip?
            """
        }

        // Tipping / culture
        if matches(lower, any: ["tip", "tipping", "etiquette", "culture", "manners"]) {
            return """
            For Atlanta, standard US tipping applies — **18–20%** at dinner (Bacchanalia will fold it into a tasting-menu gratuity), a few dollars per bag for the bell staff, and 15–20% for rideshare drivers.

            Want me to add a little tipping buffer to your expense estimate?
            """
        }

        // Loyalty / miles
        if matches(lower, any: ["miles", "points", "skymiles", "medallion", "marriott", "bonvoy", "status", "loyalty"]) {
            return """
            Your current status, snapshotted:

            • **Delta SkyMiles** — Platinum Medallion · plenty of miles for an upgrade window
            • **Marriott Bonvoy** — Titanium Elite · covers The Ritz-Carlton nights
            • **Hilton Honors** — Diamond
            • **Hertz Gold Plus** — President's Circle

            Want me to check whether an upgrade cert clears for the return leg?
            """
        }

        // Trip start / soon
        if matches(lower, any: ["atlanta", "trip", "itinerary", "board meeting", "meeting"]) {
            return """
            **Atlanta Board Meeting** — Jul 14–17:

            • Jul 14 — DL 1423 LAS → ATL · 7:00 AM · gate C22 · Seat 3A · First
            • Jul 14 — The Ritz-Carlton, Atlanta check-in · 4:00 PM
            • Jul 15 — Q3 Board Meeting · Executive Boardroom · 9:00 AM
            • Jul 15 — Dinner: **Bacchanalia** · 8:00 PM
            • Jul 17 — DL 1876 ATL → LAS · 3:00 PM

            Anything you want me to prep ahead — leave-by time, packing, dinner confirmation?
            """
        }

        // Default
        return """
        Hi — I can help you with anything across your trips. I see your **Atlanta Board Meeting** is coming up and a **Tokyo Product Summit** in September. Some things you can ask me:

        • *"When should I leave for the airport?"*
        • *"What's the status of DL 1423?"*
        • *"Submit my Atlanta expenses to Ramp"*
        • *"Build me a packing list"*
        • *"Any weather risk for my flight?"*

        What's on your mind?
        """
    }

    private static func matches(_ text: String, any keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
