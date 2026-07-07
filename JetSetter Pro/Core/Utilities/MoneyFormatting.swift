// File: Core/Utilities/MoneyFormatting.swift
//
// Shared money parsing/formatting. The same NumberFormatter setup was
// copy-pasted across the currency tracker, expense model, and IRIS context:
// decimal parsing of user input, value-only formatting with the correct
// fraction digits, and ISO-code-prefixed currency strings. Consolidated so the
// minor-unit rules (JPY/KRW → 0 decimals, USD/EUR → 2, BHD/KWD → 3) and the
// grouping/locale behavior are defined once.
//
// Pairs with `CurrencyMinorUnits`, which maps ISO 4217 codes to minor-unit
// exponents for provider APIs; this type handles user-facing display/parsing.

import Foundation

enum MoneyFormatting {

    /// Parses user-entered decimal text ("1,500.50") into a Double using the
    /// current locale's grouping/decimal separators. Returns nil for empty or
    /// unparseable input.
    ///
    /// Falls back to treating "," as a decimal separator when the locale-based
    /// parse fails, so a user typing "1,50" under a period-decimal locale still
    /// resolves to 1.5 (preserving the prior call-site behavior).
    static func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// Number of minor-unit fraction digits for an ISO 4217 code, as resolved by
    /// `NumberFormatter` (e.g. JPY → 0, USD → 2, KWD → 3).
    static func fractionDigits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }

    /// Formats a value with a fixed number of fraction digits and grouping
    /// separators, without any currency symbol or code (e.g. "1,500.00").
    static func decimalString(_ value: Double, fractionDigits digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(digits)f", value)
    }

    /// Formats a money amount for the given ISO currency code. When `includeCode`
    /// is true the ISO code is shown as a prefix ("USD 1,500.00" / "JPY 1,500");
    /// otherwise only the value is returned with the code's correct fraction
    /// digits. Falls back to a plain formatted value if the formatter fails.
    static func formatAmount(_ amount: Double, code: String, includeCode: Bool = true) -> String {
        let digits = fractionDigits(for: code)
        if includeCode {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currencyISOCode
            formatter.currencyCode = code
            if let string = formatter.string(from: NSNumber(value: amount)) {
                return string
            }
            return "\(code) \(String(format: "%.\(digits)f", amount))"
        }
        return decimalString(amount, fractionDigits: digits)
    }
}
