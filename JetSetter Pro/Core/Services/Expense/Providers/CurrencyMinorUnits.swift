// File: Core/Services/Expense/Providers/CurrencyMinorUnits.swift
//
// Shared currency helpers for expense-export providers.
//
// Provider APIs (Ramp/Brex/Divvy/Expensify) accept amounts in a currency's
// *minor units* (integer). The minor-unit count is NOT always 2: zero-decimal
// currencies (JPY, KRW, VND, …) have none, and a few (BHD, KWD, …) use three.
// Blindly multiplying by 100 sends 100x the true value for JPY and 10x for
// three-decimal currencies. This maps an ISO 4217 code to its exponent so
// callers scale correctly.

import Foundation

enum CurrencyMinorUnits {

    /// ISO 4217 currencies whose minor unit is *not* the common 2 decimals.
    /// Only the exceptions are listed; anything not present defaults to 2.
    private static let exponentOverrides: [String: Int] = [
        // Zero-decimal currencies.
        "BIF": 0, "CLP": 0, "DJF": 0, "GNF": 0, "ISK": 0, "JPY": 0,
        "KMF": 0, "KRW": 0, "PYG": 0, "RWF": 0, "UGX": 0, "VND": 0,
        "VUV": 0, "XAF": 0, "XOF": 0, "XPF": 0,
        // Three-decimal currencies.
        "BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3
    ]

    /// Number of minor-unit decimal places for an ISO 4217 code (default 2).
    static func exponent(for currencyCode: String) -> Int {
        exponentOverrides[currencyCode.uppercased()] ?? 2
    }

    /// Converts a decimal amount into the currency's integer minor units,
    /// e.g. 12.50 USD -> 1250, 1200 JPY -> 1200, 12.500 KWD -> 12500.
    static func minorUnits(_ amount: Double, currencyCode: String) -> Int {
        let factor = pow(10.0, Double(exponent(for: currencyCode)))
        return Int((amount * factor).rounded())
    }
}
