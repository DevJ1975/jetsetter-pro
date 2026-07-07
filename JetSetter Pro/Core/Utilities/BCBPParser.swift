// File: Core/Utilities/BCBPParser.swift
//
// Parser for IATA Bar Coded Boarding Pass (BCBP) data — the "M1" string encoded
// in the PDF417 barcode printed on airline boarding passes (IATA Resolution 792).
// We decode only the mandatory fixed-width fields, which is enough to prefill the
// manual flight-entry form; conditional/airline-private sections are ignored.

import Foundation

/// The subset of a boarding pass we can reliably read from the BCBP mandatory
/// fields. All fields are optional — a partial/garbled scan still prefills what
/// it can and leaves the rest for the user.
struct BoardingPass: Equatable {
    var passengerName: String?
    var pnr: String?
    var originCode: String?
    var destinationCode: String?
    var airlineCode: String?
    var flightNumber: String?   // combined, e.g. "AA 100"
    var seat: String?
    var flightDate: Date?
}

enum BCBPParser {

    /// Parses a raw BCBP payload string. Returns nil when the string doesn't look
    /// like a single-leg "M1" boarding pass or is too short to hold the mandatory
    /// section.
    static func parse(_ raw: String) -> BoardingPass? {
        // BCBP is ASCII; strip a stray trailing newline the scanner may include.
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(s)
        // Format code "M" + at least one leg, and enough length for the mandatory
        // item (60 chars through the conditional-size field).
        guard chars.count >= 60, chars.first == "M" else { return nil }

        func field(_ start: Int, _ length: Int) -> String {
            let end = min(start + length, chars.count)
            guard start < end else { return "" }
            return String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
        }

        // Fixed offsets per IATA Res. 792 mandatory section (single leg).
        let name        = field(2, 20)     // LASTNAME/FIRSTNAME
        let pnr         = field(23, 7)
        let origin      = field(30, 3)
        let destination = field(33, 3)
        let carrier     = field(36, 3)
        let flightRaw   = field(39, 5)     // e.g. "0100 "
        let julianRaw   = field(44, 3)     // day-of-year
        let seatRaw     = field(48, 4)     // e.g. "014A"

        var pass = BoardingPass()
        pass.passengerName   = formatName(name)
        pass.pnr             = nilIfEmpty(pnr)
        pass.originCode      = nilIfEmpty(origin).map { $0.uppercased() }
        pass.destinationCode = nilIfEmpty(destination).map { $0.uppercased() }
        pass.airlineCode     = nilIfEmpty(carrier).map { $0.uppercased() }
        pass.flightNumber    = composeFlightNumber(carrier: carrier, flightRaw: flightRaw)
        pass.seat            = nilIfEmpty(stripLeadingZeros(seatRaw))
        pass.flightDate      = Int(julianRaw).flatMap(dateFromDayOfYear)

        // If we recovered essentially nothing useful, treat it as a non-match.
        return pass == BoardingPass() ? nil : pass
    }

    // MARK: - Helpers

    private static func composeFlightNumber(carrier: String, flightRaw: String) -> String? {
        let code = carrier.uppercased()
        let number = stripLeadingZeros(flightRaw)
        switch (code.isEmpty, number.isEmpty) {
        case (false, false): return "\(code) \(number)"
        case (true, false):  return number
        case (false, true):  return code
        case (true, true):   return nil
        }
    }

    /// Reformats "LASTNAME/FIRSTNAME" into "Firstname Lastname" with light title-casing.
    private static func formatName(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
        let ordered: [String]
        if parts.count == 2 {
            ordered = [parts[1], parts[0]]   // first, last
        } else {
            ordered = parts
        }
        let joined = ordered.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined.capitalized
    }

    private static func stripLeadingZeros(_ s: String) -> String {
        let stripped = String(s.drop(while: { $0 == "0" }))
        return stripped.isEmpty ? s : stripped
    }

    /// Converts a 1...366 day-of-year to a concrete date. BCBP carries no year, so
    /// we resolve to the occurrence nearest to today going forward (rolling to next
    /// year when this year's date is already well in the past).
    private static func dateFromDayOfYear(_ day: Int) -> Date? {
        guard day >= 1, day <= 366 else { return nil }
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)

        func date(inYear y: Int) -> Date? {
            var jan1 = DateComponents()
            jan1.year = y
            jan1.month = 1
            jan1.day = 1
            guard let start = cal.date(from: jan1) else { return nil }
            return cal.date(byAdding: .day, value: day - 1, to: start)
        }

        guard let thisYear = date(inYear: year) else { return nil }
        // If the resolved date is more than two weeks in the past, assume it's for
        // next year (a boarding pass being entered is almost always upcoming).
        if thisYear < cal.date(byAdding: .day, value: -14, to: now)! {
            return date(inYear: year + 1)
        }
        return thisYear
    }

    private static func nilIfEmpty(_ s: String) -> String? {
        s.isEmpty ? nil : s
    }
}
