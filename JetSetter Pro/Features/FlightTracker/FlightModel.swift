// File: Features/FlightTracker/FlightModel.swift

import Foundation

// MARK: - Flight Search Response

/// Top-level response from FlightAware AeroAPI GET /flights/{ident}
struct FlightSearchResponse: Codable {
    let flights: [Flight]
    let numPages: Int
}

// MARK: - Flight

/// Represents a single flight with full status, gate, and timing information.
struct Flight: Codable, Identifiable {
    // Unique identifier generated from the FlightAware flight ID
    var id: String { faFlightId }

    let faFlightId: String
    let ident: String
    let identIata: String?
    let operatorName: String?
    let flightNumber: String?

    let origin: Airport
    let destination: Airport

    let status: String
    let aircraftType: String?

    // Gate and terminal information
    let gateOrigin: String?
    let gateDestination: String?
    let terminalOrigin: String?
    let terminalDestination: String?
    let baggageClaim: String?

    // Delay information (in seconds)
    let departureDelay: Int?
    let arrivalDelay: Int?

    // Progress (0–100)
    let progressPercent: Int?

    // Flight state flags
    let cancelled: Bool
    let diverted: Bool

    // Scheduled and estimated times (UTC)
    let scheduledOut: Date?   // Scheduled gate departure
    let estimatedOut: Date?   // Estimated gate departure
    let actualOut: Date?      // Actual gate departure

    let scheduledIn: Date?    // Scheduled gate arrival
    let estimatedIn: Date?    // Estimated gate arrival
    let actualIn: Date?       // Actual gate arrival

    // MARK: - Computed Helpers

    /// Returns true if the flight is currently airborne
    var isAirborne: Bool {
        actualOut != nil && actualIn == nil && !cancelled
    }

    /// Departure delay in minutes (positive = late, negative = early)
    var departureDelayMinutes: Int? {
        guard let seconds = departureDelay else { return nil }
        return seconds / 60
    }

    /// Arrival delay in minutes
    var arrivalDelayMinutes: Int? {
        guard let seconds = arrivalDelay else { return nil }
        return seconds / 60
    }

    /// Best available gate departure time (actual → estimated → scheduled)
    var bestDepartureTime: Date? {
        actualOut ?? estimatedOut ?? scheduledOut
    }

    /// Best available gate arrival time (actual → estimated → scheduled)
    var bestArrivalTime: Date? {
        actualIn ?? estimatedIn ?? scheduledIn
    }

    // MARK: - Codable Mapping

    enum CodingKeys: String, CodingKey {
        case faFlightId
        case ident
        case identIata
        case operatorName = "operator"
        case flightNumber
        case origin
        case destination
        case status
        case aircraftType
        case gateOrigin
        case gateDestination
        case terminalOrigin
        case terminalDestination
        case baggageClaim
        case departureDelay
        case arrivalDelay
        case progressPercent
        case cancelled
        case diverted
        case scheduledOut
        case estimatedOut
        case actualOut
        case scheduledIn
        case estimatedIn
        case actualIn
    }
}

// MARK: - Airport

/// Represents an origin or destination airport.
struct Airport: Codable {
    let code: String?
    let codeIcao: String?
    let codeIata: String?
    let name: String?
    let city: String?
    let timezone: String?

    /// Display name: prefers city name, falls back to IATA code
    var displayName: String {
        city ?? codeIata ?? code ?? "Unknown"
    }
}

// MARK: - Sample Data (used in Previews)

extension Flight {
    static let sample = Flight(
        faFlightId: "UAL2391-sample",
        ident: "UA2391",
        identIata: "UA2391",
        operatorName: "United Airlines",
        flightNumber: "2391",
        origin: Airport(
            code: "KORD",
            codeIcao: "KORD",
            codeIata: "ORD",
            name: "O'Hare International Airport",
            city: "Chicago",
            timezone: "America/Chicago"
        ),
        destination: Airport(
            code: "KJFK",
            codeIcao: "KJFK",
            codeIata: "JFK",
            name: "John F. Kennedy International Airport",
            city: "New York",
            timezone: "America/New_York"
        ),
        status: "On Time",
        aircraftType: "B737",
        gateOrigin: "B12",
        gateDestination: "C14",
        terminalOrigin: "1",
        terminalDestination: "4",
        baggageClaim: "7",
        departureDelay: 0,
        arrivalDelay: 0,
        progressPercent: 42,
        cancelled: false,
        diverted: false,
        scheduledOut: Date(),
        estimatedOut: Date(),
        actualOut: Date(),
        scheduledIn: Date().addingTimeInterval(7200),
        estimatedIn: Date().addingTimeInterval(7200),
        actualIn: nil
    )

    static let sampleDelayed = Flight(
        faFlightId: "DL445-sample",
        ident: "DL445",
        identIata: "DL445",
        operatorName: "Delta Air Lines",
        flightNumber: "445",
        origin: Airport(code: "KATL", codeIcao: "KATL", codeIata: "ATL", name: "Hartsfield-Jackson Atlanta International", city: "Atlanta", timezone: "America/New_York"),
        destination: Airport(code: "KLAX", codeIcao: "KLAX", codeIata: "LAX", name: "Los Angeles International Airport", city: "Los Angeles", timezone: "America/Los_Angeles"),
        status: "Delayed",
        aircraftType: "A321",
        gateOrigin: "A18",
        gateDestination: "42B",
        terminalOrigin: "S",
        terminalDestination: "2",
        baggageClaim: "3",
        departureDelay: 2700,
        arrivalDelay: 2700,
        progressPercent: 0,
        cancelled: false,
        diverted: false,
        scheduledOut: Date(),
        estimatedOut: Date().addingTimeInterval(2700),
        actualOut: nil,
        scheduledIn: Date().addingTimeInterval(18000),
        estimatedIn: Date().addingTimeInterval(20700),
        actualIn: nil
    )
}
