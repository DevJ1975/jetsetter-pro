// File: Core/Utilities/AirportNames.swift
//
// What to *say* for an airport code. VoiceOver reads "LAS → ATL" as "lass
// right arrow at-ul", which tells a blind traveler nothing; "Las Vegas to
// Atlanta" is the route they booked. Covers every airport in
// `AirportCoordinates` (a test keeps the two tables in step), and spells out
// any other code letter by letter rather than guessing a city.
//
// Cities with more than one major airport keep the airport in the name
// ("New York JFK", "London Heathrow"), because "New York to London" doesn't
// say which terminal to drive to.

import Foundation

nonisolated enum AirportNames {

    /// The spoken name for an IATA code ("LAS" → "Las Vegas"), or nil for an
    /// airport outside the table.
    static func spokenName(for iata: String) -> String? {
        names[iata.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    /// The spoken name, or the code spelled out ("X Y Z") when it's unknown.
    static func spokenNameOrCode(for iata: String) -> String {
        spokenName(for: iata) ?? FlightActivityFormatting.spelledCode(iata)
    }

    /// "Las Vegas to Atlanta", for a route label read by VoiceOver.
    static func spokenRoute(from origin: String, to destination: String) -> String {
        "\(spokenNameOrCode(for: origin)) to \(spokenNameOrCode(for: destination))"
    }

    /// Every code with a spoken name.
    static var knownCodes: Set<String> { Set(names.keys) }

    // MARK: - Data

    private static let names: [String: String] = [
        // ── North America ──────────────────────────────────────────────────
        "ATL": "Atlanta",
        "BOS": "Boston",
        "BWI": "Baltimore",
        "CLT": "Charlotte",
        "DCA": "Washington Reagan",
        "DEN": "Denver",
        "DFW": "Dallas Fort Worth",
        "DTW": "Detroit",
        "EWR": "Newark",
        "FLL": "Fort Lauderdale",
        "HNL": "Honolulu",
        "IAD": "Washington Dulles",
        "IAH": "Houston",
        "JFK": "New York JFK",
        "LAS": "Las Vegas",
        "LAX": "Los Angeles",
        "LGA": "New York LaGuardia",
        "MCO": "Orlando",
        "MIA": "Miami",
        "MSP": "Minneapolis",
        "ORD": "Chicago O'Hare",
        "PHL": "Philadelphia",
        "PHX": "Phoenix",
        "SAN": "San Diego",
        "SEA": "Seattle",
        "SFO": "San Francisco",
        "SLC": "Salt Lake City",
        "MEX": "Mexico City",
        "YUL": "Montreal",
        "YVR": "Vancouver",
        "YYC": "Calgary",
        "YYZ": "Toronto",

        // ── South America ──────────────────────────────────────────────────
        "BOG": "Bogotá",
        "EZE": "Buenos Aires",
        "GRU": "São Paulo",
        "LIM": "Lima",
        "SCL": "Santiago",

        // ── Europe ─────────────────────────────────────────────────────────
        "AMS": "Amsterdam",
        "ARN": "Stockholm",
        "ATH": "Athens",
        "BCN": "Barcelona",
        "BER": "Berlin",
        "CDG": "Paris Charles de Gaulle",
        "CPH": "Copenhagen",
        "DUB": "Dublin",
        "FCO": "Rome",
        "FRA": "Frankfurt",
        "HEL": "Helsinki",
        "IST": "Istanbul",
        "LGW": "London Gatwick",
        "LHR": "London Heathrow",
        "LIS": "Lisbon",
        "MAD": "Madrid",
        "MUC": "Munich",
        "MXP": "Milan Malpensa",
        "ORY": "Paris Orly",
        "OSL": "Oslo",
        "VIE": "Vienna",
        "ZRH": "Zurich",

        // ── Middle East & Africa ──────────────────────────────────────────
        "AUH": "Abu Dhabi",
        "CAI": "Cairo",
        "CPT": "Cape Town",
        "DOH": "Doha",
        "DXB": "Dubai",
        "JNB": "Johannesburg",

        // ── Asia & Pacific ────────────────────────────────────────────────
        "BKK": "Bangkok",
        "CAN": "Guangzhou",
        "DEL": "Delhi",
        "HAN": "Hanoi",
        "HKG": "Hong Kong",
        "HND": "Tokyo Haneda",
        "ICN": "Seoul Incheon",
        "KIX": "Osaka Kansai",
        "KUL": "Kuala Lumpur",
        "MNL": "Manila",
        "NRT": "Tokyo Narita",
        "PEK": "Beijing",
        "PVG": "Shanghai Pudong",
        "SGN": "Ho Chi Minh City",
        "SIN": "Singapore",
        "TPE": "Taipei",
        "BOM": "Mumbai",

        // ── Oceania ───────────────────────────────────────────────────────
        "AKL": "Auckland",
        "BNE": "Brisbane",
        "MEL": "Melbourne",
        "PER": "Perth",
        "SYD": "Sydney"
    ]
}
