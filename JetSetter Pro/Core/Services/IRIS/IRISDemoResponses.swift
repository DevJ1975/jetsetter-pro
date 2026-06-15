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

        // Weather
        if matches(lower, any: ["weather", "rain", "forecast", "umbrella"]) {
            return """
            Let's see… Tokyo is looking pleasant for your trip — about **18°C** and partly cloudy mid-week, with light evening showers possible Thursday. I'd toss a compact umbrella in your carry-on and pack a layer for evenings.

            Want me to add an umbrella reminder to your packing list?
            """
        }

        // Visa / entry
        if matches(lower, any: ["visa", "passport", "entry", "japan rules", "immigration"]) {
            return """
            Japan is **visa-free** for US passport holders up to 90 days — you're set. Your passport needs to be valid through the duration of stay (no extra-month buffer required).

            I'd save a digital copy of your hotel reservation; immigration sometimes asks for it at landing. Want me to surface it from your Travel Wallet now?
            """
        }

        // Departure / leave
        if matches(lower, any: ["leave", "depart", "when should i", "uber", "lyft", "traffic"]) {
            return """
            Based on current traffic on the Van Wyck and TSA wait at **JFK Terminal 8**, I'd suggest leaving at **8:47 PM**. That puts you airside by 10:15 PM, with a 90-minute cushion before boarding.

            Want me to set a 15-minute departure alert and pre-stage an Uber Black?
            """
        }

        // Expenses / submit
        if matches(lower, any: ["expense", "submit", "report", "approver", "ramp", "concur"]) {
            return """
            I can send your **Tokyo Business Summit** report straight to one of your connected providers (Expensify, Ramp, Brex, BILL) or as a polished PDF to your approver. Six items so far, total ¥95,900 (about **$647 USD**) — all categorized.

            One tap — should I queue it up?
            """
        }

        // Packing
        if matches(lower, any: ["pack", "packing", "what to bring", "luggage list"]) {
            return """
            For Tokyo in business mode, I'd plan around:

            • 3 light suits (navy + charcoal), neutral shoes
            • Compact umbrella + a layer for evenings (~18°C mid-week)
            • Power adapter (Type A)
            • Hotel + visa-free entry confirmations saved offline

            I noted you're vegetarian — I'll flag a few restaurants near the venue that handle it gracefully. Want me to build the full list?
            """
        }

        // Hotel
        if matches(lower, any: ["hotel", "stay", "room", "park hyatt", "booking"]) {
            return """
            You're booked at the **Park Hyatt Tokyo** (Park Suite, 48th floor, city view) for 6 nights starting Thursday — confirmation **PHT-2026-78451**.

            Want me to email the concierge ahead about your dietary preferences and the **8:00 PM dinner reservation at Sukiyabashi Jiro** on Day 4?
            """
        }

        // Flight status
        if matches(lower, any: ["flight", "aa169", "aa170", "delay", "gate", "status"]) {
            return """
            Your outbound **AA169 (JFK → NRT)** is currently **on time**. Departure 11:45 PM, gate **B22**, Terminal 8. Seat 3A, Business — Boeing 787-9.

            Your return AA170 has been flagged with a **45-minute delay** — I've already lined up 3 alternative flights. Want to review them?
            """
        }

        // Disruption
        if matches(lower, any: ["disruption", "cancelled", "rebook", "alternative", "missed connection"]) {
            return """
            Good thinking. Your **AA170 NRT → JFK** return is currently delayed 45 minutes. I've already done the work:

            • **DL182** — departs 24 min later, $1,320 Business · 12 seats
            • **JL004** — departs 28 min later, $1,485 Business · 6 seats
            • **NH008** — departs 32 min later, $1,690 Business · 3 seats

            I'd nudge you toward DL182 — cheapest, plenty of availability, and lands close to your original arrival window. Should I open the rebooking?
            """
        }

        // Currency
        if matches(lower, any: ["currency", "yen", "exchange", "jpy", "convert"]) {
            return """
            Current rate: **1 USD ≈ 148 JPY** as of an hour ago. Your Tokyo trip so far: **¥95,900 spent (~$647 USD)** — biggest line is the omakase at Jiro.

            I'd recommend pulling cash at a 7-Eleven ATM on arrival (lowest spread) rather than the airport kiosks. Want a heads-up on rate changes during your trip?
            """
        }

        // Tipping / culture
        if matches(lower, any: ["tip", "tipping", "etiquette", "culture", "manners"]) {
            return """
            In Japan, **tipping is generally not expected — and can sometimes be considered rude**. Exceptional service is the baseline. A polite *"arigato gozaimasu"* and a small bow go further than cash.

            For hotel staff who help with bags or arrange car service, a small thanks is enough. Save the tipping habit for back home.
            """
        }

        // Loyalty / miles
        if matches(lower, any: ["miles", "points", "aadvantage", "marriott", "bonvoy", "status", "loyalty"]) {
            return """
            Your current status, snapshotted:

            • **American AAdvantage** — Platinum Pro · 247,830 miles · expires Feb 2027
            • **Marriott Bonvoy** — Titanium Elite · 184,200 points · April 2026
            • **Hilton Honors** — Diamond · 92,400 points
            • **Emirates Skywards** — Gold · 88,500 miles

            Marriott Bonvoy expires in 4 months — you'll cross renewal with the Park Hyatt nights. Want me to flag any upgrade certs you could burn?
            """
        }

        // Trip start / soon
        if matches(lower, any: ["tokyo", "trip", "itinerary", "summit"]) {
            return """
            **Tokyo Business Summit** kicks off in **3 days**:

            • Day 1 — AA169 JFK → NRT · 11:45 PM · B22 · Seat 3A · Business
            • Day 2 — Park Hyatt Tokyo check-in · 3:00 PM
            • Days 3-5 — Global Innovators Summit · Tokyo International Forum
            • Day 4 — Dinner: **Sukiyabashi Jiro** · 8:00 PM · party of 4
            • Day 7 — AA170 NRT → JFK · 6:00 PM · gate C14

            Anything you want me to prep ahead — weather, packing, restaurant confirmations?
            """
        }

        // Default
        return """
        Hi — I can help you with anything across your trips. I see your **Tokyo Business Summit** is 3 days out and your **Dubai Luxury Retreat** is in 3 weeks. Some things you can ask me:

        • *"What's the weather in Tokyo?"*
        • *"Do I need a visa for Japan?"*
        • *"When should I leave for the airport?"*
        • *"Submit my Tokyo expenses to Ramp"*
        • *"Build me a packing list"*

        What's on your mind?
        """
    }

    private static func matches(_ text: String, any keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
