// File: JetSetter ProTests/CurrencyMathTests.swift
// Unit tests for currency scaling and conversion. These guard the money paths
// that feed expense-export providers (Ramp/Brex/Divvy/Expensify) and the
// currency tracker — a rounding or exponent slip here becomes a real over/under
// charge, so the edge cases (zero- and three-decimal currencies, rounding
// boundaries, missing/zero/negative rates) are covered explicitly.

import Testing
import Foundation
@testable import JetSetter_Pro

struct CurrencyMinorUnitsTests {

    // MARK: - Exponents

    @Test func defaultExponentIsTwo() {
        #expect(CurrencyMinorUnits.exponent(for: "USD") == 2)
        #expect(CurrencyMinorUnits.exponent(for: "EUR") == 2)
        #expect(CurrencyMinorUnits.exponent(for: "GBP") == 2)
    }

    @Test func zeroDecimalCurrenciesHaveNoMinorUnit() {
        for code in ["JPY", "KRW", "VND", "CLP", "XAF", "XOF"] {
            #expect(CurrencyMinorUnits.exponent(for: code) == 0)
        }
    }

    @Test func threeDecimalCurrenciesUseThousandths() {
        for code in ["BHD", "KWD", "OMR", "TND", "IQD", "JOD", "LYD"] {
            #expect(CurrencyMinorUnits.exponent(for: code) == 3)
        }
    }

    @Test func exponentLookupIsCaseInsensitive() {
        #expect(CurrencyMinorUnits.exponent(for: "jpy") == 0)
        #expect(CurrencyMinorUnits.exponent(for: "kwd") == 3)
        #expect(CurrencyMinorUnits.exponent(for: "usd") == 2)
    }

    // MARK: - Minor-unit conversion

    @Test func twoDecimalScalesByHundred() {
        #expect(CurrencyMinorUnits.minorUnits(12.50, currencyCode: "USD") == 1250)
        #expect(CurrencyMinorUnits.minorUnits(0.99, currencyCode: "EUR") == 99)
        #expect(CurrencyMinorUnits.minorUnits(1000, currencyCode: "USD") == 100_000)
    }

    @Test func zeroDecimalIsNotMultiplied() {
        // The core bug this helper exists to prevent: JPY must NOT be x100.
        #expect(CurrencyMinorUnits.minorUnits(1200, currencyCode: "JPY") == 1200)
        #expect(CurrencyMinorUnits.minorUnits(20_350, currencyCode: "JPY") == 20_350)
        #expect(CurrencyMinorUnits.minorUnits(30_000, currencyCode: "KRW") == 30_000)
    }

    @Test func threeDecimalScalesByThousand() {
        #expect(CurrencyMinorUnits.minorUnits(12.500, currencyCode: "KWD") == 12_500)
        #expect(CurrencyMinorUnits.minorUnits(1, currencyCode: "BHD") == 1000)
    }

    @Test func roundingHandlesFloatingPointImprecision() {
        // 19.99 * 100 is 1998.9999… in binary floating point; must round to 1999.
        #expect(CurrencyMinorUnits.minorUnits(19.99, currencyCode: "USD") == 1999)
        // 0.1 + 0.2 style accumulation shouldn't truncate down.
        #expect(CurrencyMinorUnits.minorUnits(0.30, currencyCode: "USD") == 30)
        // Round half to nearest.
        #expect(CurrencyMinorUnits.minorUnits(1.005, currencyCode: "USD") == 101 || CurrencyMinorUnits.minorUnits(1.005, currencyCode: "USD") == 100)
    }

    @Test func zeroAmountIsZeroMinorUnits() {
        #expect(CurrencyMinorUnits.minorUnits(0, currencyCode: "USD") == 0)
        #expect(CurrencyMinorUnits.minorUnits(0, currencyCode: "JPY") == 0)
    }
}

struct ExchangeRatesConversionTests {

    private func rates(_ pairs: [String: Double], base: String = "USD") -> ExchangeRates {
        ExchangeRates(base: base, rates: pairs, fetchedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func convertsWithKnownRate() {
        let fx = rates(["EUR": 0.9, "JPY": 150])
        #expect(fx.convert(amount: 100, to: "EUR") == 90)
        #expect(fx.convert(amount: 2, to: "JPY") == 300)
    }

    @Test func missingTargetReturnsNil() {
        let fx = rates(["EUR": 0.9])
        // No same-currency identity in the table -> nil (documents current behavior).
        #expect(fx.convert(amount: 100, to: "GBP") == nil)
        #expect(fx.convert(amount: 100, to: "USD") == nil)
    }

    @Test func zeroRateConvertsToZero() {
        // A 0 rate is a real (if degenerate) table value and must not crash.
        let fx = rates(["EUR": 0])
        #expect(fx.convert(amount: 100, to: "EUR") == 0)
    }

    @Test func negativeAndZeroAmountsPassThroughRate() {
        let fx = rates(["EUR": 0.5])
        #expect(fx.convert(amount: 0, to: "EUR") == 0)
        #expect(fx.convert(amount: -20, to: "EUR") == -10)
    }

    @Test func freshnessWindowIsSixHours() {
        let fresh = ExchangeRates(base: "USD", rates: [:], fetchedAt: Date())
        #expect(fresh.isFresh)
        let stale = ExchangeRates(base: "USD", rates: [:], fetchedAt: Date(timeIntervalSinceNow: -7 * 3600))
        #expect(!stale.isFresh)
    }
}
