// File: Core/Services/EmailIntelligence/ParsedTravelModels.swift
//
// Shared data contract for the Email Intelligence feature: the structured
// entities the AI extracts from a forwarded travel email.
//
// Two representations:
//   1. Plain Codable DTOs (below) — decoded from the Claude JSON fallback and
//      used by every downstream consumer (review UI, commit service). These,
//      plus `TravelEmailPrompt`, are the Android-portable contract: Gemini
//      Nano on Android should target the exact same JSON schema.
//   2. `@Generable` mirrors (bottom, iOS 26+) — the same shapes expressed for
//      Apple's on-device FoundationModels guided generation, mapped back to
//      the DTOs via `toDTO()`.

import Foundation
import FoundationModels

// MARK: - Envelope

nonisolated struct ParsedTravelEmail: Codable {
    var flights: [ParsedFlight] = []
    var hotels: [ParsedHotel] = []
    var carRentals: [ParsedCarRental] = []
    var meetings: [ParsedMeeting] = []
    var disruptions: [ParsedDisruptionNotice] = []

    enum CodingKeys: String, CodingKey {
        case flights, hotels
        case carRentals = "car_rentals"
        case meetings, disruptions
    }

    init() {}

    // Lenient decoding — the model may omit empty arrays entirely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flights     = (try? c.decodeIfPresent([ParsedFlight].self,           forKey: .flights))     .flatMap { $0 } ?? []
        hotels      = (try? c.decodeIfPresent([ParsedHotel].self,            forKey: .hotels))      .flatMap { $0 } ?? []
        carRentals  = (try? c.decodeIfPresent([ParsedCarRental].self,        forKey: .carRentals))  .flatMap { $0 } ?? []
        meetings    = (try? c.decodeIfPresent([ParsedMeeting].self,          forKey: .meetings))    .flatMap { $0 } ?? []
        disruptions = (try? c.decodeIfPresent([ParsedDisruptionNotice].self, forKey: .disruptions)) .flatMap { $0 } ?? []
    }

    var isEmpty: Bool {
        flights.isEmpty && hotels.isEmpty && carRentals.isEmpty
            && meetings.isEmpty && disruptions.isEmpty
    }

    var entityCount: Int {
        flights.count + hotels.count + carRentals.count + meetings.count + disruptions.count
    }

    /// Merge entities from another parse (used when processing several
    /// forwarded emails in one review session).
    mutating func merge(_ other: ParsedTravelEmail) {
        flights.append(contentsOf: other.flights)
        hotels.append(contentsOf: other.hotels)
        carRentals.append(contentsOf: other.carRentals)
        meetings.append(contentsOf: other.meetings)
        disruptions.append(contentsOf: other.disruptions)
    }
}

// MARK: - Entities
//
// Every `id` is local-only (excluded from CodingKeys) so the review UI can
// track selection; dates travel as "yyyy-MM-dd'T'HH:mm" strings in the LOCAL
// time of the venue/airport as stated in the email — we deliberately do not
// guess timezone conversions (flagged in the review UI instead).

nonisolated struct ParsedFlight: Identifiable, Codable {
    let id = UUID()
    var airline: String? = nil
    var flightNumber: String
    var departureAirport: String? = nil   // IATA, e.g. "JFK"
    var arrivalAirport: String? = nil
    var departureLocal: String? = nil     // "2026-08-15T18:25"
    var arrivalLocal: String? = nil
    var seat: String? = nil
    var gate: String? = nil
    var terminal: String? = nil
    var confirmationNumber: String? = nil
    var confidence: Double = 0.5

    enum CodingKeys: String, CodingKey {
        case airline
        case flightNumber = "flight_number"
        case departureAirport = "departure_airport"
        case arrivalAirport = "arrival_airport"
        case departureLocal = "departure_local"
        case arrivalLocal = "arrival_local"
        case seat, gate, terminal
        case confirmationNumber = "confirmation_number"
        case confidence
    }

    var fingerprint: String {
        let key = confirmationNumber ?? flightNumber
        return "flight|\(key.uppercased())|\(String((departureLocal ?? "").prefix(10)))"
    }
}

nonisolated struct ParsedHotel: Identifiable, Codable {
    let id = UUID()
    var name: String
    var address: String? = nil
    var checkInLocal: String? = nil
    var checkOutLocal: String? = nil
    var confirmationNumber: String? = nil
    var confidence: Double = 0.5

    enum CodingKeys: String, CodingKey {
        case name, address
        case checkInLocal = "check_in_local"
        case checkOutLocal = "check_out_local"
        case confirmationNumber = "confirmation_number"
        case confidence
    }

    var fingerprint: String {
        "hotel|\((confirmationNumber ?? name).uppercased())|\(String((checkInLocal ?? "").prefix(10)))"
    }
}

nonisolated struct ParsedCarRental: Identifiable, Codable {
    let id = UUID()
    var company: String
    var pickupLocation: String? = nil
    var pickupLocal: String? = nil
    var dropoffLocal: String? = nil
    var vehicleClass: String? = nil
    var confirmationNumber: String? = nil
    var confidence: Double = 0.5

    enum CodingKeys: String, CodingKey {
        case company
        case pickupLocation = "pickup_location"
        case pickupLocal = "pickup_local"
        case dropoffLocal = "dropoff_local"
        case vehicleClass = "vehicle_class"
        case confirmationNumber = "confirmation_number"
        case confidence
    }

    var fingerprint: String {
        "car|\((confirmationNumber ?? company).uppercased())|\(String((pickupLocal ?? "").prefix(10)))"
    }
}

nonisolated struct ParsedMeeting: Identifiable, Codable {
    let id = UUID()
    var title: String
    var startLocal: String? = nil
    var endLocal: String? = nil
    var location: String? = nil
    var organizer: String? = nil
    var notes: String? = nil
    var confidence: Double = 0.5

    enum CodingKeys: String, CodingKey {
        case title
        case startLocal = "start_local"
        case endLocal = "end_local"
        case location, organizer, notes, confidence
    }

    var fingerprint: String {
        "meeting|\(title.uppercased())|\(String((startLocal ?? "").prefix(16)))"
    }
}

nonisolated struct ParsedDisruptionNotice: Identifiable, Codable {
    let id = UUID()
    /// "cancellation", "delay", or "gate_change"
    var kind: String
    var flightNumber: String
    var airline: String? = nil
    var origin: String? = nil
    var destination: String? = nil
    var scheduledDepartureLocal: String? = nil
    var delayMinutes: Int? = nil
    var newGate: String? = nil
    var details: String? = nil
    var confidence: Double = 0.5

    enum CodingKeys: String, CodingKey {
        case kind
        case flightNumber = "flight_number"
        case airline, origin, destination
        case scheduledDepartureLocal = "scheduled_departure_local"
        case delayMinutes = "delay_minutes"
        case newGate = "new_gate"
        case details, confidence
    }

    var fingerprint: String {
        "disruption|\(kind)|\(flightNumber.uppercased())|\(String((scheduledDepartureLocal ?? "").prefix(10)))"
    }
}

// MARK: - Date parsing helper

nonisolated enum TravelDateParser {

    /// Tolerantly parses the local-time strings the model emits.
    /// Interpreted in the device's current timezone (we don't guess venue
    /// timezones — the review UI flags this).
    static func date(from string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else {
            return nil
        }
        // Full ISO 8601 with timezone, if the model included one
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFractional.date(from: string) { return d }
        if let d = ISO8601DateFormatter().date(from: string) { return d }

        // Local formats (no timezone)
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = format
            if let d = f.date(from: string) { return d }
        }
        return nil
    }
}

// MARK: - Shared prompt (Android-portable contract)

nonisolated enum TravelEmailPrompt {

    /// System instructions used by BOTH the on-device session and the Claude
    /// fallback (and, later, Gemini Nano on Android).
    static let instructions = """
    You are a travel-email extraction engine inside a travel app. The user forwards you raw \
    travel-related emails (airline confirmations, hotel bookings, car rentals, meeting/calendar \
    invitations, and airline disruption notices). Extract ONLY information explicitly present in \
    the email — never invent values. Dates and times must be kept in the LOCAL time stated in the \
    email, formatted as yyyy-MM-dd'T'HH:mm (24-hour). If a field is absent, omit it. Set \
    confidence between 0 and 1 for each extracted item. Marketing emails, newsletters, and \
    receipts that are not bookings contain no entities — return empty lists for them.
    """

    /// JSON output contract appended for the cloud (Claude) path. On-device
    /// guided generation enforces the equivalent schema natively.
    static let jsonContract = """
    Return ONLY a JSON object — no markdown fences, no explanation — with exactly these keys \
    (arrays may be empty):
    {
      "flights": [{ "airline": string?, "flight_number": string, "departure_airport": string?, \
    "arrival_airport": string?, "departure_local": string?, "arrival_local": string?, \
    "seat": string?, "gate": string?, "terminal": string?, "confirmation_number": string?, \
    "confidence": number }],
      "hotels": [{ "name": string, "address": string?, "check_in_local": string?, \
    "check_out_local": string?, "confirmation_number": string?, "confidence": number }],
      "car_rentals": [{ "company": string, "pickup_location": string?, "pickup_local": string?, \
    "dropoff_local": string?, "vehicle_class": string?, "confirmation_number": string?, \
    "confidence": number }],
      "meetings": [{ "title": string, "start_local": string?, "end_local": string?, \
    "location": string?, "organizer": string?, "notes": string?, "confidence": number }],
      "disruptions": [{ "kind": "cancellation"|"delay"|"gate_change", "flight_number": string, \
    "airline": string?, "origin": string?, "destination": string?, \
    "scheduled_departure_local": string?, "delay_minutes": integer?, "new_gate": string?, \
    "details": string?, "confidence": number }]
    }
    Airport codes must be 3-letter IATA. Flight numbers like "AA100". Use meetings for calendar \
    invites, meeting requests, and event confirmations that are not flights/hotels/cars.
    """
}

// MARK: - On-device guided-generation mirrors (iOS 26+)
//
// Same shapes as the DTOs above, expressed for FoundationModels. Kept in sync
// by hand — if you add a field, add it in both places and in `jsonContract`.

@available(iOS 26.0, *)
@Generable
struct ParsedFlightGen {
    @Guide(description: "Airline name, e.g. 'Delta Air Lines'. Omit if not stated.")
    var airline: String?
    @Guide(description: "Flight number like 'AA100'.")
    var flightNumber: String
    @Guide(description: "3-letter IATA departure airport code, e.g. 'JFK'.")
    var departureAirport: String?
    @Guide(description: "3-letter IATA arrival airport code.")
    var arrivalAirport: String?
    @Guide(description: "Departure in local time as yyyy-MM-dd'T'HH:mm.")
    var departureLocal: String?
    @Guide(description: "Arrival in local time as yyyy-MM-dd'T'HH:mm.")
    var arrivalLocal: String?
    @Guide(description: "Seat like '12A', if stated.")
    var seat: String?
    @Guide(description: "Gate, if stated.")
    var gate: String?
    @Guide(description: "Terminal, if stated.")
    var terminal: String?
    @Guide(description: "Booking confirmation / record locator, if stated.")
    var confirmationNumber: String?
    @Guide(description: "Extraction confidence from 0 to 1.")
    var confidence: Double

    func toDTO() -> ParsedFlight {
        var f = ParsedFlight(flightNumber: flightNumber)
        f.airline = airline
        f.departureAirport = departureAirport
        f.arrivalAirport = arrivalAirport
        f.departureLocal = departureLocal
        f.arrivalLocal = arrivalLocal
        f.seat = seat
        f.gate = gate
        f.terminal = terminal
        f.confirmationNumber = confirmationNumber
        f.confidence = confidence
        return f
    }
}

@available(iOS 26.0, *)
@Generable
struct ParsedHotelGen {
    @Guide(description: "Hotel name.")
    var name: String
    @Guide(description: "Street address, if stated.")
    var address: String?
    @Guide(description: "Check-in local time as yyyy-MM-dd'T'HH:mm (or date-only yyyy-MM-dd).")
    var checkInLocal: String?
    @Guide(description: "Check-out local time as yyyy-MM-dd'T'HH:mm (or date-only).")
    var checkOutLocal: String?
    @Guide(description: "Confirmation number, if stated.")
    var confirmationNumber: String?
    @Guide(description: "Extraction confidence from 0 to 1.")
    var confidence: Double

    func toDTO() -> ParsedHotel {
        var h = ParsedHotel(name: name)
        h.address = address
        h.checkInLocal = checkInLocal
        h.checkOutLocal = checkOutLocal
        h.confirmationNumber = confirmationNumber
        h.confidence = confidence
        return h
    }
}

@available(iOS 26.0, *)
@Generable
struct ParsedCarRentalGen {
    @Guide(description: "Rental company, e.g. 'Hertz'.")
    var company: String
    @Guide(description: "Pickup location, if stated.")
    var pickupLocation: String?
    @Guide(description: "Pickup local time as yyyy-MM-dd'T'HH:mm.")
    var pickupLocal: String?
    @Guide(description: "Drop-off local time as yyyy-MM-dd'T'HH:mm.")
    var dropoffLocal: String?
    @Guide(description: "Vehicle class, if stated.")
    var vehicleClass: String?
    @Guide(description: "Confirmation number, if stated.")
    var confirmationNumber: String?
    @Guide(description: "Extraction confidence from 0 to 1.")
    var confidence: Double

    func toDTO() -> ParsedCarRental {
        var c = ParsedCarRental(company: company)
        c.pickupLocation = pickupLocation
        c.pickupLocal = pickupLocal
        c.dropoffLocal = dropoffLocal
        c.vehicleClass = vehicleClass
        c.confirmationNumber = confirmationNumber
        c.confidence = confidence
        return c
    }
}

@available(iOS 26.0, *)
@Generable
struct ParsedMeetingGen {
    @Guide(description: "Meeting or event title.")
    var title: String
    @Guide(description: "Start in local time as yyyy-MM-dd'T'HH:mm.")
    var startLocal: String?
    @Guide(description: "End in local time as yyyy-MM-dd'T'HH:mm, if stated.")
    var endLocal: String?
    @Guide(description: "Location or video-call link, if stated.")
    var location: String?
    @Guide(description: "Organizer name or email, if stated.")
    var organizer: String?
    @Guide(description: "Any agenda/notes worth keeping, briefly.")
    var notes: String?
    @Guide(description: "Extraction confidence from 0 to 1.")
    var confidence: Double

    func toDTO() -> ParsedMeeting {
        var m = ParsedMeeting(title: title)
        m.startLocal = startLocal
        m.endLocal = endLocal
        m.location = location
        m.organizer = organizer
        m.notes = notes
        m.confidence = confidence
        return m
    }
}

@available(iOS 26.0, *)
@Generable
struct ParsedDisruptionNoticeGen {
    @Guide(description: "One of: cancellation, delay, gate_change.")
    var kind: String
    @Guide(description: "Affected flight number like 'AA100'.")
    var flightNumber: String
    @Guide(description: "Airline name, if stated.")
    var airline: String?
    @Guide(description: "Origin IATA code, if stated.")
    var origin: String?
    @Guide(description: "Destination IATA code, if stated.")
    var destination: String?
    @Guide(description: "Originally scheduled departure, local, yyyy-MM-dd'T'HH:mm.")
    var scheduledDepartureLocal: String?
    @Guide(description: "Delay in minutes, if this is a delay.")
    var delayMinutes: Int?
    @Guide(description: "New gate, if this is a gate change.")
    var newGate: String?
    @Guide(description: "One-line summary of the notice.")
    var details: String?
    @Guide(description: "Extraction confidence from 0 to 1.")
    var confidence: Double

    func toDTO() -> ParsedDisruptionNotice {
        var d = ParsedDisruptionNotice(kind: kind, flightNumber: flightNumber)
        d.airline = airline
        d.origin = origin
        d.destination = destination
        d.scheduledDepartureLocal = scheduledDepartureLocal
        d.delayMinutes = delayMinutes
        d.newGate = newGate
        d.details = details
        d.confidence = confidence
        return d
    }
}

@available(iOS 26.0, *)
@Generable
struct ParsedTravelEmailGen {
    @Guide(description: "Flights confirmed in the email. Empty if none.")
    var flights: [ParsedFlightGen]
    @Guide(description: "Hotel reservations in the email. Empty if none.")
    var hotels: [ParsedHotelGen]
    @Guide(description: "Car rentals in the email. Empty if none.")
    var carRentals: [ParsedCarRentalGen]
    @Guide(description: "Meetings, invites, and non-travel events. Empty if none.")
    var meetings: [ParsedMeetingGen]
    @Guide(description: "Airline cancellation/delay/gate-change notices. Empty if none.")
    var disruptions: [ParsedDisruptionNoticeGen]

    func toDTO() -> ParsedTravelEmail {
        var result = ParsedTravelEmail()
        result.flights = flights.map { $0.toDTO() }
        result.hotels = hotels.map { $0.toDTO() }
        result.carRentals = carRentals.map { $0.toDTO() }
        result.meetings = meetings.map { $0.toDTO() }
        result.disruptions = disruptions.map { $0.toDTO() }
        return result
    }
}
