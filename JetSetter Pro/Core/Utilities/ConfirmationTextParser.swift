// File: Core/Utilities/ConfirmationTextParser.swift
//
// Best-effort heuristic parser for pasted booking-confirmation text (e.g. a
// forwarded airline/hotel/rental email). It extracts a few high-signal fields to
// PREFILL the manual-entry form — it is deliberately conservative and always
// leaves the user in the editable form to confirm. Not a reliable structured
// parser; only fields matched with high confidence are returned.

import Foundation

/// Fields we attempt to recover from pasted confirmation text. All optional.
struct ParsedConfirmation: Equatable {
    var confirmationNumber: String?
    var originCode: String?
    var destinationCode: String?
    var amount: Double?
    var currencyCode: String?

    var isEmpty: Bool { self == ParsedConfirmation() }
}

enum ConfirmationTextParser {

    static func parse(_ text: String) -> ParsedConfirmation {
        var result = ParsedConfirmation()
        result.confirmationNumber = confirmationCode(in: text)
        if let route = route(in: text) {
            result.originCode = route.0
            result.destinationCode = route.1
        }
        if let money = amount(in: text) {
            result.amount = money.0
            result.currencyCode = money.1
        }
        return result
    }

    // MARK: - Confirmation code

    /// Looks for a labeled confirmation/booking/PNR code, e.g. "Confirmation #: ABC123".
    private static func confirmationCode(in text: String) -> String? {
        let pattern = #"(?:confirmation|booking|reservation|record\s*locator|itinerary|pnr)"# +
                      #"(?:\s*(?:number|code|reference|ref|id|no\.?|#))?\s*[:#\-]?\s*([A-Z0-9]{5,8})\b"#
        guard let match = firstMatch(pattern, in: text, options: [.caseInsensitive]),
              let code = group(1, match, text) else { return nil }
        return code.uppercased()
    }

    // MARK: - Route

    /// Matches an IATA pair like "SFO → JFK", "SFO-JFK", or "SFO to JFK".
    private static func route(in text: String) -> (String, String)? {
        let pattern = #"\b([A-Z]{3})\s*(?:->|→|–|—|-|to)\s*([A-Z]{3})\b"#
        guard let match = firstMatch(pattern, in: text, options: []),
              let origin = group(1, match, text),
              let destination = group(2, match, text) else { return nil }
        // Guard against three-letter English words masquerading as codes only when
        // paired with "to" — the arrow/dash forms are unambiguous enough to keep.
        return (origin.uppercased(), destination.uppercased())
    }

    // MARK: - Amount + currency

    private static let symbolToCode: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY"
    ]

    private static let knownCodes = [
        "USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "CNY",
        "HKD", "SGD", "AED", "MXN", "BRL", "INR", "NZD"
    ]

    /// Extracts a total/price and its currency. Tries symbol-prefixed ("$1,299.00"),
    /// then code-prefixed ("USD 1299"), then amount-then-code ("1299 EUR").
    private static func amount(in text: String) -> (Double, String)? {
        let number = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#

        // $1,299.00
        if let match = firstMatch(#"([$€£¥])\s*"# + number, in: text, options: []),
           let symbol = group(1, match, text), let raw = group(2, match, text),
           let value = MoneyFormatting.parseDecimal(raw), let code = symbolToCode[symbol] {
            return (value, code)
        }

        let codeAlt = knownCodes.joined(separator: "|")

        // USD 1,299.00
        if let match = firstMatch(#"\b("# + codeAlt + #")\s*"# + number, in: text, options: [.caseInsensitive]),
           let code = group(1, match, text), let raw = group(2, match, text),
           let value = MoneyFormatting.parseDecimal(raw) {
            return (value, code.uppercased())
        }

        // 1,299.00 USD
        if let match = firstMatch(number + #"\s*\b("# + codeAlt + #")\b"#, in: text, options: [.caseInsensitive]),
           let raw = group(1, match, text), let code = group(2, match, text),
           let value = MoneyFormatting.parseDecimal(raw) {
            return (value, code.uppercased())
        }

        return nil
    }

    // MARK: - Regex helpers

    private static func firstMatch(_ pattern: String, in text: String,
                                   options: NSRegularExpression.Options) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
