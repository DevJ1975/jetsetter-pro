// File: Features/FlightBoard/FlightBoardData.swift
//
// Generates a plausible departure board that merges the user's own flight
// (when one exists in the itinerary) into a chronologically ordered list of
// curated illustrative departures. The user flight is not pinned to the top —
// it slots in by its real scheduled time and stays visually distinct via
// `isUserFlight` styling.

import Foundation

enum FlightBoardData {

    /// Builds a board for the current moment. Pulls the user's next flight
    /// from `jetsetter_trips` and intermixes it with sample departures.
    static func generate() -> [FlightBoardRow] {
        var rows = sampleDepartures()

        if let userFlight = loadUserFlightRow() {
            rows.append(userFlight)
        }

        // Present a believable "Departures" board: order chronologically by the
        // real scheduled instant so the user's flight slots in where it actually
        // belongs (it stays visually distinct via `isUserFlight` styling) instead
        // of being pinned above flights that leave sooner. Rows without a parseable
        // date (only a far-future user flight ever lacks one) sort to the end.
        return rows.sorted { lhs, rhs in
            switch (lhs.departureDate, rhs.departureDate) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return false
            }
        }
    }

    // MARK: - User flight extraction

    private static func loadUserFlightRow() -> FlightBoardRow? {
        guard let trips = CodableDefaults.load([Trip].self, forKey: "jetsetter_trips") else { return nil }

        let now = Date()
        let upcoming = trips
            .flatMap { $0.items }
            .filter { $0.type == .flight && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }

        guard let next = upcoming.first else { return nil }

        let flightNumber = extractFlightNumber(from: next.title) ?? "—"
        let destIATA = extractDestinationIATA(location: next.location, title: next.title) ?? "—"
        let gate = extractGate(from: next.notes) ?? "TBD"
        // Only claim a terminal when the itinerary actually states one (or one can
        // be inferred from the gate letter). Defaulting to "1" would file the real
        // flight under an unrelated fictional terminal and hide it when the user
        // filters to a different terminal. Unknown terminals ("") are surfaced only
        // under "ALL".
        let terminal = extractTerminal(from: next.notes)
            ?? terminalFromGate(gate)
            ?? ""

        // Pick a status based on how close departure is
        let minutesAway = Int(next.startDate.timeIntervalSinceNow / 60)

        // The board mixes the user's flight with same-day sample departures, so
        // only surface it while it's within the board's realistic horizon
        // (~6 hours). Beyond that, a bare "HH:mm" would read as a today's
        // departure — so prefix the date to avoid confusion.
        let isToday = Calendar.current.isDateInToday(next.startDate)
        guard isToday || minutesAway < 360 else {
            // Far-future flight: keep it on the board but make the date explicit.
            let dated = DateFormatter()
            dated.dateFormat = "MMM d HH:mm"
            return FlightBoardRow(
                flightNumber: flightNumber,
                destinationIATA: destIATA,
                destinationName: destIATA,
                scheduledTime: dated.string(from: next.startDate).uppercased(),
                gate: gate,
                terminal: terminal,
                status: .onTime,
                isUserFlight: true,
                departureDate: next.startDate
            )
        }

        let f = DateFormatter()
        f.dateFormat = "HH:mm"

        return FlightBoardRow(
            flightNumber: flightNumber,
            destinationIATA: destIATA,
            destinationName: destIATA,
            scheduledTime: f.string(from: next.startDate),
            gate: gate,
            terminal: terminal,
            status: BoardStatus.live(minutesAway: minutesAway),
            isUserFlight: true,
            departureDate: next.startDate
        )
    }

    /// Infers a terminal from a gate label when the gate is lettered per terminal
    /// (e.g. "C14" → "C"). Returns `nil` for numeric-only or missing gates so the
    /// caller can fall back to an unknown terminal rather than guessing.
    private static func terminalFromGate(_ gate: String) -> String? {
        guard let first = gate.first, first.isLetter else { return nil }
        return String(first)
    }

    private static func extractFlightNumber(from title: String) -> String? {
        let normalized = title.replacingOccurrences(
            of: #"([A-Z]{2,3})\s+(\d)"#,
            with: "$1$2",
            options: .regularExpression
        )
        guard let range = normalized.range(of: #"\b[A-Z]{2,3}\d{1,4}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(normalized[range])
    }

    /// Best-effort destination IATA. Trips are free-text, so accept the common
    /// separators writers/users produce ("→", "->", " to ", "-") and, failing
    /// that, fall back to the last standalone 3-letter uppercase token found in
    /// the location (then the title). Returns `nil` when nothing plausible is
    /// present so the caller can render a placeholder.
    private static func extractDestinationIATA(location: String?, title: String?) -> String? {
        if let location, !location.isEmpty {
            // Try the "ORIGIN <sep> DEST" shapes, longest/most-specific first.
            for separator in [" → ", "→", " -> ", "->", " to ", " - "] {
                let parts = location.components(separatedBy: separator)
                if parts.count > 1,
                   let dest = parts.last?.trimmingCharacters(in: .whitespaces),
                   !dest.isEmpty {
                    if let iata = iataToken(in: dest) { return iata }
                    return dest
                }
            }
            if let iata = iataToken(in: location) { return iata }
        }
        if let title, let iata = iataToken(in: title) { return iata }
        return nil
    }

    /// Returns the last standalone 3-letter uppercase token (a plausible IATA
    /// code) in the string, or `nil` if there isn't one.
    private static func iataToken(in text: String) -> String? {
        var matched: String?
        var searchStart = text.startIndex
        while let range = text.range(
            of: #"\b[A-Z]{3}\b"#,
            options: .regularExpression,
            range: searchStart..<text.endIndex
        ) {
            matched = String(text[range])
            searchStart = range.upperBound
        }
        return matched
    }

    private static func extractGate(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: #"Gate\s+([A-Z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return String(notes[range])
            .replacingOccurrences(of: #"^Gate\s+"#, with: "", options: .regularExpression)
    }

    private static func extractTerminal(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: #"Terminal\s+([A-Z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return String(notes[range])
            .replacingOccurrences(of: #"^Terminal\s+"#, with: "", options: .regularExpression)
    }

    // MARK: - Sample departures

    /// Plausible curated departures from a busy international airport.
    /// Times shift relative to "now" so they always feel fresh.
    private static func sampleDepartures() -> [FlightBoardRow] {
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "HH:mm"

        let templates: [(String, String, Int, String, String, BoardStatus)] = [
            ("UA837",  "LHR", 18, "C14", "3", .boarding),
            ("AF023",  "CDG", 45, "B22", "1", .onTime),
            ("LH441",  "FRA", 62, "A7",  "1", .onTime),
            ("DL400",  "AMS", 80, "B18", "2", .delayed),
            ("BA178",  "MAD", 95, "C9",  "3", .onTime),
            ("EK202",  "DXB", 110, "A12", "1", .onTime),
            ("AA169",  "GRU", 125, "D4",  "4", .onTime),
            ("SQ026",  "SIN", 140, "A18", "1", .boarding),
            ("JL004",  "HND", 165, "B7",  "2", .onTime),
            ("QF008",  "SYD", 190, "C22", "3", .onTime),
            ("KL642",  "FCO", 210, "B25", "2", .onTime),
            ("LX040",  "ZRH", 230, "A3",  "1", .delayed),
            ("AC859",  "YYZ", 250, "D11", "4", .onTime),
            ("CX841",  "HKG", 280, "C18", "3", .onTime)
        ]

        return templates.map { (flight, dest, minutes, gate, terminal, editorialStatus) in
            let scheduled = now.addingTimeInterval(TimeInterval(minutes * 60))
            // Keep editorial states (.delayed/.cancelled) as authored; otherwise
            // derive the status from the schedule so it advances live and matches
            // the user flight's thresholds.
            let status: BoardStatus = (editorialStatus == .delayed || editorialStatus == .cancelled)
                ? editorialStatus
                : BoardStatus.live(minutesAway: minutes)
            return FlightBoardRow(
                flightNumber: flight,
                destinationIATA: dest,
                destinationName: dest,
                scheduledTime: f.string(from: scheduled),
                gate: gate,
                terminal: terminal,
                status: status,
                departureDate: scheduled
            )
        }
    }
}
