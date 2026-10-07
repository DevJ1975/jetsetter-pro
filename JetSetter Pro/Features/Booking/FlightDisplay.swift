// File: Features/Booking/FlightDisplay.swift
//
// Offer and booking -> display mapping, kept pure so it can be tested without a
// view. The rules it enforces:
//
//  * Departure is shown in the ORIGIN airport's zone and arrival in the
//    DESTINATION airport's, never the phone's. When neither the server nor the
//    app's airport table knows the zone, the wall clock is shown exactly as the
//    server sent it (read in UTC and printed in UTC, so the digits can't shift).
//  * An arrival on a later (or earlier) local date than the departure gets a
//    "+1" / "−1" mark.
//  * Anything the server didn't say renders as "—" or "not provided", never as
//    a guess. A missing refund rule is NOT shown as "refundable".

import Foundation

// MARK: - Display values

nonisolated struct SegmentDisplay: Equatable, Sendable, Identifiable {
    let id: Int
    let flightNumber: String
    let carrierName: String?
    let originCode: String
    let destinationCode: String
    let departureTime: String
    let arrivalTime: String
    let departureDate: String
    let arrivalDayOffset: Int
    let durationText: String?
    let aircraft: String?
    let originTerminal: String?
    let destinationTerminal: String?

    var arrivalDayLabel: String? { FlightDisplay.dayOffsetLabel(arrivalDayOffset) }
}

nonisolated struct SliceDisplay: Equatable, Sendable {
    let routeLabel: String
    /// "Las Vegas to Atlanta", for VoiceOver.
    let spokenRoute: String
    let departureTime: String
    let arrivalTime: String
    let departureDate: String
    let arrivalDayOffset: Int
    let durationText: String?
    let stopsText: String
    let fareBrand: String?
    let segments: [SegmentDisplay]

    var arrivalDayLabel: String? { FlightDisplay.dayOffsetLabel(arrivalDayOffset) }

    /// "9:05 AM – 4:15 PM +1"
    var timeRange: String {
        var text = "\(departureTime) – \(arrivalTime)"
        if let label = arrivalDayLabel { text += " \(label)" }
        return text
    }
}

// MARK: - Sorting

nonisolated enum OfferSort: String, CaseIterable, Identifiable, Sendable {
    case price, duration, stops

    var id: String { rawValue }

    var label: String {
        switch self {
        case .price:    return "Cheapest"
        case .duration: return "Fastest"
        case .stops:    return "Fewest stops"
        }
    }
}

// MARK: - Mapping

nonisolated enum FlightDisplay {

    // MARK: Slices and segments

    static func slice(_ slice: BackendSlice, locale: Locale = .autoupdatingCurrent) -> SliceDisplay {
        let segments = slice.segments.enumerated().map { index, segment in
            Self.segment(segment, id: index, locale: locale)
        }
        let first = slice.segments.first
        let last = slice.segments.last

        let origin = slice.origin.iataCode
        let destination = slice.destination.iataCode
        let spokenOrigin = slice.origin.cityName ?? AirportNames.spokenNameOrCode(for: origin)
        let spokenDestination = slice.destination.cityName ?? AirportNames.spokenNameOrCode(for: destination)

        let offset: Int
        if let first, let last {
            offset = BackendDates.dayOffset(departing: first.departingAt, arriving: last.arrivingAt) ?? 0
        } else {
            offset = 0
        }

        return SliceDisplay(
            routeLabel: "\(origin) → \(destination)",
            spokenRoute: "\(spokenOrigin) to \(spokenDestination)",
            departureTime: first.map { wallTime($0.departingAt, at: $0.origin, locale: locale) } ?? "—",
            arrivalTime: last.map { wallTime($0.arrivingAt, at: $0.destination, locale: locale) } ?? "—",
            departureDate: first.map { wallDate($0.departingAt, at: $0.origin, locale: locale) } ?? "—",
            arrivalDayOffset: offset,
            durationText: BackendDuration.display(slice.duration),
            stopsText: stopsText(slice),
            fareBrand: slice.fareBrandName,
            segments: segments
        )
    }

    static func segment(_ segment: BackendSegment, id: Int, locale: Locale = .autoupdatingCurrent) -> SegmentDisplay {
        SegmentDisplay(
            id: id,
            flightNumber: flightNumber(segment, fallbackCarrier: nil) ?? "—",
            carrierName: segment.operatingCarrier?.name ?? segment.marketingCarrier?.name,
            originCode: segment.origin.iataCode,
            destinationCode: segment.destination.iataCode,
            departureTime: wallTime(segment.departingAt, at: segment.origin, locale: locale),
            arrivalTime: wallTime(segment.arrivingAt, at: segment.destination, locale: locale),
            departureDate: wallDate(segment.departingAt, at: segment.origin, locale: locale),
            arrivalDayOffset: BackendDates.dayOffset(departing: segment.departingAt, arriving: segment.arrivingAt) ?? 0,
            durationText: BackendDuration.display(segment.duration),
            aircraft: nonEmpty(segment.aircraft),
            originTerminal: nonEmpty(segment.originTerminal),
            destinationTerminal: nonEmpty(segment.destinationTerminal)
        )
    }

    /// "9:05 AM" (or "09:05" for a 24-hour locale) at `airport`.
    static func wallTime(_ raw: String, at airport: BackendAirport, locale: Locale = .autoupdatingCurrent) -> String {
        format(raw, at: airport, style: .time, locale: locale)
    }

    /// "Mon, Nov 2, 2026" at `airport`.
    static func wallDate(_ raw: String, at airport: BackendAirport, locale: Locale = .autoupdatingCurrent) -> String {
        format(raw, at: airport, style: .weekdayDate, locale: locale)
    }

    private static func format(
        _ raw: String, at airport: BackendAirport,
        style: AppDateFormatters.AirportTimeStyle, locale: Locale
    ) -> String {
        // Unknown zone: read the digits in UTC and print them in UTC, which
        // shows the airport's wall clock unchanged.
        let zone = BackendDates.zone(for: airport) ?? TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let instant = BackendDates.instant(raw, in: zone) else { return "—" }
        return AppDateFormatters.airportTime(instant, in: zone, style: style, locale: locale)
    }

    static func dayOffsetLabel(_ offset: Int) -> String? {
        switch offset {
        case 0: return nil
        case let n where n > 0: return "+\(n)"
        default: return "−\(abs(offset))"
        }
    }

    static func stopsText(_ slice: BackendSlice) -> String {
        guard slice.stops > 0 else { return "Nonstop" }
        let noun = slice.stops == 1 ? "1 stop" : "\(slice.stops) stops"
        let via = slice.segments.dropLast().map(\.destination.iataCode)
        return via.isEmpty ? noun : "\(noun) · \(via.joined(separator: ", "))"
    }

    /// The full designator ("DL1423"). The server already sends it complete; a
    /// bare number is prefixed with the carrier code so the app's single flight
    /// number parser (`TravelStore.extractFlightNumber`) can read it.
    static func flightNumber(_ segment: BackendSegment, fallbackCarrier: BackendCarrier?) -> String? {
        let raw = segment.flightNumber?
            .filter { !$0.isWhitespace }
            .uppercased() ?? ""
        guard !raw.isEmpty else { return nil }
        if raw.allSatisfy(\.isNumber) {
            let code = segment.marketingCarrier?.iataCode ?? fallbackCarrier?.iataCode
            if let code = nonEmpty(code) { return code.uppercased() + raw }
        }
        return raw
    }

    // MARK: Cabin, conditions, baggage

    static func cabinName(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch value {
        case "economy":         return "Economy"
        case "premium_economy": return "Premium Economy"
        case "business":        return "Business"
        case "first":           return "First"
        case "":                return nil
        default:                return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func refundSummary(_ conditions: BackendConditions?, locale: Locale = .autoupdatingCurrent) -> String {
        ruleSummary(conditions?.refundBeforeDeparture,
                    unknown: "Refund terms not provided",
                    notAllowed: "Non-refundable",
                    free: "Refundable",
                    withFee: "Refundable", locale: locale)
    }

    static func changeSummary(_ conditions: BackendConditions?, locale: Locale = .autoupdatingCurrent) -> String {
        ruleSummary(conditions?.changeBeforeDeparture,
                    unknown: "Change terms not provided",
                    notAllowed: "Changes not allowed",
                    free: "Free changes",
                    withFee: "Changes allowed", locale: locale)
    }

    private static func ruleSummary(
        _ rule: BackendConditionRule?, unknown: String, notAllowed: String,
        free: String, withFee: String, locale: Locale
    ) -> String {
        guard let allowed = rule?.allowed else { return unknown }
        guard allowed else { return notAllowed }
        if let amount = rule?.penaltyAmount, !BackendMoney.isZero(amount) {
            let fee = BackendMoney.display(amount, currency: rule?.penaltyCurrency, locale: locale)
            return "\(withFee) · \(fee) fee"
        }
        return free
    }

    static func baggageSummary(_ baggage: [BackendBaggage]) -> String {
        guard !baggage.isEmpty else { return "Baggage not specified" }
        var parts: [String] = []
        if let checked = baggage.first(where: { $0.type == "checked" }) {
            switch checked.quantity {
            case 0:  parts.append("No checked bag")
            case 1:  parts.append("1 checked bag")
            default: parts.append("\(checked.quantity) checked bags")
            }
        }
        if let carryOn = baggage.first(where: { $0.type == "carry_on" }) {
            parts.append(carryOn.quantity == 0 ? "No carry-on" : "\(carryOn.quantity) carry-on")
        }
        return parts.isEmpty ? "Baggage not specified" : parts.joined(separator: " · ")
    }

    static func passengerSummary(_ passengers: [BackendOfferPassenger]) -> String {
        let count = passengers.count
        return count == 1 ? "1 traveler" : "\(count) travelers"
    }

    // MARK: Sorting

    static func totalMinutes(_ offer: BackendOffer) -> Int {
        var total = 0
        for slice in offer.slices {
            guard let minutes = BackendDuration.minutes(slice.duration) else { return Int.max }
            total += minutes
        }
        return total
    }

    static func totalStops(_ offer: BackendOffer) -> Int {
        offer.slices.reduce(0) { $0 + $1.stops }
    }

    /// Sorts without disturbing the server's order among equals (cheapest
    /// first), so "Fastest" breaks ties by price.
    static func sorted(_ offers: [BackendOffer], by sort: OfferSort) -> [BackendOffer] {
        let byPrice = offers.enumerated().sorted { lhs, rhs in
            let a = BackendMoney.decimal(lhs.element.totalAmount) ?? .greatestFiniteMagnitude
            let b = BackendMoney.decimal(rhs.element.totalAmount) ?? .greatestFiniteMagnitude
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
        switch sort {
        case .price:
            return byPrice
        case .duration:
            return byPrice.enumerated().sorted { lhs, rhs in
                let a = totalMinutes(lhs.element), b = totalMinutes(rhs.element)
                return a == b ? lhs.offset < rhs.offset : a < b
            }.map(\.element)
        case .stops:
            return byPrice.enumerated().sorted { lhs, rhs in
                let a = totalStops(lhs.element), b = totalStops(rhs.element)
                return a == b ? lhs.offset < rhs.offset : a < b
            }.map(\.element)
        }
    }

    // MARK: Helpers

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
