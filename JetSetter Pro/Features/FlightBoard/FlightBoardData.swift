// File: Features/FlightBoard/FlightBoardData.swift
//
// Generates a plausible departure board that includes the user's own flight
// (when one exists in the itinerary) at the top, followed by curated
// fictional departures from the same airport/terminal.

import Foundation

enum FlightBoardData {

    /// Builds a board for the current moment. Pulls the user's next flight
    /// from `jetsetter_trips` and intermixes it with sample departures.
    static func generate() -> [FlightBoardRow] {
        var rows: [FlightBoardRow] = []

        if let userFlight = loadUserFlightRow() {
            rows.append(userFlight)
        }

        rows.append(contentsOf: sampleDepartures())
        return rows
    }

    // MARK: - User flight extraction

    private static func loadUserFlightRow() -> FlightBoardRow? {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let trips = try? decoder.decode([Trip].self, from: data) else { return nil }

        let now = Date()
        let upcoming = trips
            .flatMap { $0.items }
            .filter { $0.type == .flight && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }

        guard let next = upcoming.first else { return nil }

        let flightNumber = extractFlightNumber(from: next.title) ?? "—"
        let parts = (next.location ?? "").components(separatedBy: " → ")
        let destIATA = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "—"
        let gate = extractGate(from: next.notes) ?? "TBD"
        let terminal = extractTerminal(from: next.notes) ?? "1"

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
                isUserFlight: true
            )
        }

        let f = DateFormatter()
        f.dateFormat = "HH:mm"

        let status: BoardStatus
        switch minutesAway {
        case ..<15:    status = .finalCall
        case 15..<45:  status = .boarding
        default:       status = .onTime
        }

        return FlightBoardRow(
            flightNumber: flightNumber,
            destinationIATA: destIATA,
            destinationName: destIATA,
            scheduledTime: f.string(from: next.startDate),
            gate: gate,
            terminal: terminal,
            status: status,
            isUserFlight: true
        )
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

    private static func extractGate(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: #"Gate\s+([A-Z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return String(notes[range]).replacingOccurrences(of: "Gate ", with: "")
    }

    private static func extractTerminal(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: #"Terminal\s+([A-Z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return String(notes[range]).replacingOccurrences(of: "Terminal ", with: "")
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

        return templates.map { (flight, dest, minutes, gate, terminal, status) in
            let scheduled = now.addingTimeInterval(TimeInterval(minutes * 60))
            return FlightBoardRow(
                flightNumber: flight,
                destinationIATA: dest,
                destinationName: dest,
                scheduledTime: f.string(from: scheduled),
                gate: gate,
                terminal: terminal,
                status: status
            )
        }
    }
}
