// File: Core/Services/BookingCapture.swift
//
// Captures a booking the traveler made somewhere else — an airline site, an
// online travel agent, a hotel's own page — without retyping it.
//
// Everything here runs on the device. Apple Intelligence reads the confirmation
// and returns structured fields; when it isn't available (iOS 18, unsupported
// hardware, model still downloading) the regex parser in ConfirmationTextParser
// fills what it can. The two are merged, model first, so the result degrades
// instead of disappearing.
//
// Text can arrive by paste or by photo: a screenshot of a confirmation goes
// through Vision OCR and then the same extractor, because screenshotting the
// confirmation is what people actually do.

import Foundation
import UIKit
import FoundationModels

/// A booking recovered from free text. Every field is optional — the form the
/// user lands on is still editable, and nothing is ever saved unreviewed.
nonisolated struct ParsedBooking: Equatable {

    enum Kind: String, Equatable {
        case flight, hotel, carRental, other

        var itemType: ItineraryItemType {
            switch self {
            case .flight:    return .flight
            case .hotel:     return .hotel
            case .carRental: return .transport
            case .other:     return .activity
            }
        }
    }

    var kind: Kind = .other
    /// True when `kind` came from a source that actually decided. The model must
    /// be able to say "other" and have that answer survive the merge, which a
    /// bare `== .other` check would treat as "nothing said".
    var kindIsExplicit = false
    var confirmationNumber: String?
    var provider: String?          // airline, hotel chain, rental company
    var title: String?

    // Flight
    var flightNumber: String?
    var originCode: String?
    var destinationCode: String?
    var seat: String?
    var cabinClass: String?
    var terminal: String?
    var gate: String?

    // Hotel / car
    var address: String?
    var roomType: String?
    var pickupLocation: String?
    var dropoffLocation: String?

    // Timing
    var startDate: Date?
    var endDate: Date?

    // Money
    var amount: Double?
    var currencyCode: String?

    var isEmpty: Bool { self == ParsedBooking() }

    /// Fills any field this booking is missing from `other`. Used to layer the
    /// regex result underneath the model result.
    func merging(_ other: ParsedBooking) -> ParsedBooking {
        var out = self
        // Only a self that expressed no opinion adopts the other's kind. An
        // explicit .other from the model is an answer, not a blank.
        if out.kind == .other, !out.kindIsExplicit {
            out.kind = other.kind
            out.kindIsExplicit = other.kindIsExplicit
        }
        out.confirmationNumber = out.confirmationNumber ?? other.confirmationNumber
        out.provider = out.provider ?? other.provider
        out.title = out.title ?? other.title
        out.flightNumber = out.flightNumber ?? other.flightNumber
        out.originCode = out.originCode ?? other.originCode
        out.destinationCode = out.destinationCode ?? other.destinationCode
        out.seat = out.seat ?? other.seat
        out.cabinClass = out.cabinClass ?? other.cabinClass
        out.terminal = out.terminal ?? other.terminal
        out.gate = out.gate ?? other.gate
        out.address = out.address ?? other.address
        out.roomType = out.roomType ?? other.roomType
        out.pickupLocation = out.pickupLocation ?? other.pickupLocation
        out.dropoffLocation = out.dropoffLocation ?? other.dropoffLocation
        out.startDate = out.startDate ?? other.startDate
        out.endDate = out.endDate ?? other.endDate
        out.amount = out.amount ?? other.amount
        out.currencyCode = out.currencyCode ?? other.currencyCode
        return out
    }
}

@MainActor
final class BookingCapture {

    static let shared = BookingCapture()
    private init() {}

    /// True when Apple Intelligence can do the full extraction. False means the
    /// regex fallback runs alone, which recovers fewer fields.
    var isIntelligenceAvailable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: - Entry points

    /// Reads a pasted confirmation.
    func booking(fromText text: String) async -> ParsedBooking {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ParsedBooking() }

        let heuristic = Self.heuristicBooking(from: trimmed)
        guard #available(iOS 26.0, *), isIntelligenceAvailable else { return heuristic }
        guard let extracted = await extractOnDevice(from: trimmed, routeHint: heuristic) else { return heuristic }
        // Model first, regex underneath.
        return extracted.merging(heuristic)
    }

    /// Reads a screenshot or photo of a confirmation.
    func booking(fromImage image: UIImage) async throws -> ParsedBooking {
        let text = try await VisionOCRService.shared.text(in: image)
        return await booking(fromText: text)
    }

    // MARK: - Apple Intelligence

    @available(iOS 26.0, *)
    private func extractOnDevice(from text: String, routeHint: ParsedBooking) async -> ParsedBooking? {
        let session = LanguageModelSession(instructions: """
        You read travel booking confirmations — airline, hotel, rental car and \
        rail — and extract the booking into structured fields.

        Rules:
        - Copy values exactly as printed. Never invent a value that is not in the text.
        - Leave a field empty when the text does not state it. An empty field is \
          always better than a guess.
        - Airport codes are the three-letter IATA codes.
        - Write dates and times as ISO 8601, for example 2026-09-14T07:00:00.
        - The amount is the total the traveler paid, not a nightly rate, tax line \
          or fare component.
        """)

        do {
            let response = try await session.respond(
                to: "Booking confirmation:\n\(text.prefix(4000))",
                generating: ExtractedBooking.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return Self.booking(from: response.content, routeHint: routeHint)
        } catch {
            return nil
        }
    }

    /// `routeHint` is the regex result. Its airports only pick the zone for the
    /// model's times when the model didn't name the airports itself, so the
    /// zone always matches the route the merged booking ends up with (model
    /// first, regex underneath).
    @available(iOS 26.0, *)
    private static func booking(from extracted: ExtractedBooking, routeHint: ParsedBooking) -> ParsedBooking {
        func clean(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  trimmed.lowercased() != "unknown",
                  trimmed != "-" else { return nil }
            return trimmed
        }
        func code(_ value: String?) -> String? {
            guard let raw = clean(value)?.uppercased(), raw.count == 3, raw.allSatisfy(\.isLetter) else { return nil }
            return raw
        }

        var booking = ParsedBooking()
        booking.kind = ParsedBooking.Kind(rawValue: extracted.kind.lowercased())
            ?? (extracted.kind.lowercased() == "car" ? .carRental : .other)
        booking.kindIsExplicit = true
        booking.confirmationNumber = clean(extracted.confirmationNumber)?.uppercased()
        booking.provider = clean(extracted.provider)
        booking.title = clean(extracted.title)
        booking.flightNumber = clean(extracted.flightNumber)?.uppercased()
        booking.originCode = code(extracted.originCode)
        booking.destinationCode = code(extracted.destinationCode)
        booking.seat = clean(extracted.seat)?.uppercased()
        booking.cabinClass = clean(extracted.cabinClass)
        booking.terminal = clean(extracted.terminal)?.uppercased()
        booking.gate = clean(extracted.gate)?.uppercased()
        booking.address = clean(extracted.address)
        let times = Self.bookingTimes(
            start: clean(extracted.startDateISO8601),
            end: clean(extracted.endDateISO8601),
            isFlight: booking.kind == .flight,
            originCode: booking.originCode ?? routeHint.originCode,
            destinationCode: booking.destinationCode ?? routeHint.destinationCode
        )
        booking.startDate = times.start
        booking.endDate = times.end
        if let amount = extracted.totalAmount, amount > 0 { booking.amount = amount }
        if let currency = clean(extracted.currencyCode)?.uppercased(),
           currency.count == 3, Locale.commonISOCurrencyCodes.contains(currency) {
            booking.currencyCode = currency
        }
        return booking
    }

    // MARK: - Dates

    /// Parses the ISO-8601 shapes a language model realistically emits, with and
    /// without a time or a zone. Anything else is dropped rather than guessed.
    ///
    /// A string with a zone ("Z", "-07:00") is an absolute instant and ignores
    /// `timeZone`. A zoneless one ("2026-09-14T09:05:00") is a wall-clock time
    /// and is read in `timeZone`, which defaults to the device's zone.
    static func date(from raw: String?, in timeZone: TimeZone = .current) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        let withZone = ISO8601DateFormatter()
        withZone.formatOptions = [.withInternetDateTime]
        if let parsed = withZone.date(from: raw) { return parsed }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: raw) { return parsed }

        // Local formats: the model is told to omit the zone and copy times as
        // printed, and a confirmation prints each time at its own airport, so
        // the caller picks the zone (see `bookingTimes`).
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) { return parsed }
        }
        return nil
    }

    /// Turns the model's start and end strings into instants. A flight
    /// confirmation prints departure at the origin airport and arrival at the
    /// destination, so for a flight each zoneless time is read in its own
    /// airport's zone. Anything else, or an airport `AirportCoordinates` doesn't
    /// know, keeps the device zone as before. So does a bare date with no clock
    /// time: it names a day, and the form's date picker reads days on the
    /// phone's calendar, so airport midnight could show as the day before.
    ///
    /// The defect this covers: every time was read in the device zone, so
    /// "DL1423 LAS→ATL departs 9:05 AM" pasted on a phone set to Atlanta was
    /// saved as 9:05 Eastern, three hours early.
    static func bookingTimes(
        start: String?,
        end: String?,
        isFlight: Bool,
        originCode: String?,
        destinationCode: String?
    ) -> (start: Date?, end: Date?) {
        func zone(for raw: String?, at iata: String?) -> TimeZone {
            guard isFlight, let raw, raw.contains(":"),
                  let iata, let airport = AirportCoordinates.timeZone(for: iata) else { return .current }
            return airport
        }
        return (
            date(from: start, in: zone(for: start, at: originCode)),
            date(from: end, in: zone(for: end, at: destinationCode))
        )
    }

    // MARK: - Regex fallback

    /// The no-Apple-Intelligence path: the existing conservative parser, plus a
    /// flight number and a booking-kind guess from the same text.
    static func heuristicBooking(from text: String) -> ParsedBooking {
        let parsed = ConfirmationTextParser.parse(text)
        var booking = ParsedBooking()
        booking.confirmationNumber = parsed.confirmationNumber
        booking.originCode = parsed.originCode
        booking.destinationCode = parsed.destinationCode
        booking.amount = parsed.amount
        booking.currencyCode = parsed.currencyCode
        booking.flightNumber = TravelStore.extractFlightNumber(from: text)
        booking.kind = kind(of: text, hasRoute: parsed.originCode != nil, hasFlight: booking.flightNumber != nil)
        return booking
    }

    private static func kind(of text: String, hasRoute: Bool, hasFlight: Bool) -> ParsedBooking.Kind {
        if hasFlight || hasRoute { return .flight }
        // Whole words only. Substring matching made "dinner" contain "inn" and
        // classified a restaurant confirmation as a hotel.
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let phrases = text.lowercased()
        let hotelWords: Set<String> = ["hotel", "resort", "inn", "suite", "nights", "room", "checkin", "checkout"]
        let hotelPhrases = ["check-in", "check in", "check-out", "check out"]
        let carWords: Set<String> = ["hertz", "avis", "enterprise", "sixt", "budget", "alamo", "vehicle"]
        let carPhrases = ["rental car", "car rental", "pick-up location", "pickup location", "drop-off", "dropoff"]
        let carScore = words.intersection(carWords).count + carPhrases.filter { phrases.contains($0) }.count
        let hotelScore = words.intersection(hotelWords).count + hotelPhrases.filter { phrases.contains($0) }.count
        if carScore > 0, carScore >= hotelScore { return .carRental }
        if hotelScore > 0 { return .hotel }
        return .other
    }
}

// MARK: - Generable schema

/// The shape Apple Intelligence fills in. Every field is optional except the
/// kind, so the model can leave out what the confirmation does not say.
@available(iOS 26.0, *)
@Generable
nonisolated struct ExtractedBooking {
    @Guide(description: "What was booked", .anyOf(["flight", "hotel", "car", "other"]))
    var kind: String

    @Guide(description: "Confirmation, booking reference or record locator, exactly as printed")
    var confirmationNumber: String?

    @Guide(description: "Company that sold or operates the booking, e.g. Delta Air Lines, Marriott, Hertz")
    var provider: String?

    @Guide(description: "A short human title for this booking, e.g. 'Delta DL1423' or 'The Ritz-Carlton, Atlanta'")
    var title: String?

    @Guide(description: "Flight number including the airline code, e.g. DL1423. Empty when this is not a flight")
    var flightNumber: String?

    @Guide(description: "Three-letter IATA code of the departure airport")
    var originCode: String?

    @Guide(description: "Three-letter IATA code of the arrival airport")
    var destinationCode: String?

    @Guide(description: "Seat assignment, e.g. 14A")
    var seat: String?

    @Guide(description: "Cabin or fare class, e.g. Economy, Business, First")
    var cabinClass: String?

    @Guide(description: "Departure terminal")
    var terminal: String?

    @Guide(description: "Departure gate")
    var gate: String?

    @Guide(description: "Street address of the hotel or rental counter")
    var address: String?

    @Guide(description: "Start in ISO 8601: departure for a flight, check-in for a hotel, pickup for a car")
    var startDateISO8601: String?

    @Guide(description: "End in ISO 8601: arrival for a flight, check-out for a hotel, drop-off for a car")
    var endDateISO8601: String?

    @Guide(description: "Total amount paid, as a decimal number")
    var totalAmount: Double?

    @Guide(description: "ISO 4217 currency code of the total, e.g. USD, EUR, GBP")
    var currencyCode: String?
}
