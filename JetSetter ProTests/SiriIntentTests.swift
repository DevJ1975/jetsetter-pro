// File: JetSetter ProTests/SiriIntentTests.swift
//
// Siri answers that must follow the traveler rather than a US default: the
// currency an expense is logged in, the unit a temperature is spoken in, and
// which intents refuse to run on a locked phone. Pure helpers with explicit
// locales, so the result doesn't depend on the simulator's region.

import Testing
import Foundation
import AppIntents
@testable import JetSetter_Pro

struct SiriIntentTests {

    // MARK: - Log Expense currency

    /// Defect this covers: "Log Expense" defaulted to USD, so a traveler whose
    /// home currency is EUR had a 40-euro lunch saved as $40 whenever they
    /// didn't say the currency word.
    @Test func unspokenCurrencyUsesTheHomeCurrency() {
        #expect(LogExpenseIntent.currencyCode(spoken: nil, homeCode: "EUR") == "EUR")
        #expect(LogExpenseIntent.currencyCode(spoken: "  ", homeCode: "JPY") == "JPY")
    }

    @Test func aSpokenCurrencyWinsOverTheHomeCurrency() {
        #expect(LogExpenseIntent.currencyCode(spoken: "pounds", homeCode: "EUR") == "GBP")
        #expect(LogExpenseIntent.currencyCode(spoken: "usd", homeCode: "EUR") == "USD")
    }

    @Test func anUnclearCurrencyAsksAgainInsteadOfGuessing() {
        #expect(LogExpenseIntent.currencyCode(spoken: "shells", homeCode: "EUR") == nil)
        #expect(LogExpenseIntent.currencyCode(spoken: nil, homeCode: nil) == nil)
    }

    @Test func homeCurrencyPrefersTheSettingsChoice() {
        #expect(HomeCurrency.code(preference: "GBP", locale: Locale(identifier: "de_DE")) == "GBP")
    }

    @Test func homeCurrencyFallsBackToTheRegionsCurrency() {
        #expect(HomeCurrency.code(preference: nil, locale: Locale(identifier: "de_DE")) == "EUR")
        #expect(HomeCurrency.code(preference: nil, locale: Locale(identifier: "ja_JP")) == "JPY")
        #expect(HomeCurrency.code(preference: "not a currency", locale: Locale(identifier: "en_GB")) == "GBP")
    }

    // MARK: - Spoken temperature

    /// Defect this covers: Siri always said °F, so a traveler in Europe heard
    /// "It's 72°F" about their destination.
    @Test func temperatureIsSpokenInCelsiusWhereTheLocaleUsesIt() {
        let german = SpokenWeather.temperature(fahrenheit: 72, locale: Locale(identifier: "de_DE"))
        #expect(german.contains("22"))
        #expect(german.contains("°C"))
        #expect(!german.contains("°F"))
    }

    @Test func temperatureStaysInFahrenheitForUSLocales() {
        let american = SpokenWeather.temperature(fahrenheit: 72, locale: Locale(identifier: "en_US"))
        #expect(american.contains("72"))
        #expect(american.contains("°F"))
    }

    @Test func freezingConvertsToZeroCelsius() {
        let french = SpokenWeather.temperature(fahrenheit: 32, locale: Locale(identifier: "fr_FR"))
        #expect(french.contains("0"))
        #expect(french.contains("°C"))
    }

    // MARK: - Locked phone

    @Test func intentsThatTouchPersonalDataNeedAnUnlockedPhone() {
        #expect(LogExpenseIntent.authenticationPolicy == .requiresAuthentication)
        #expect(RememberPreferenceIntent.authenticationPolicy == .requiresAuthentication)
        #expect(TravelPersonaIntent.authenticationPolicy == .requiresAuthentication)
        #expect(NextFlightIntent.authenticationPolicy == .requiresAuthentication)
        #expect(NextTripIntent.authenticationPolicy == .requiresAuthentication)
        #expect(DepartureBriefingIntent.authenticationPolicy == .requiresAuthentication)
        #expect(DestinationWeatherIntent.authenticationPolicy == .requiresAuthentication)
        #expect(BagStatusIntent.authenticationPolicy == .requiresAuthentication)
        #expect(CheckInIntent.authenticationPolicy == .requiresAuthentication)
        #expect(GeneratePackingListIntent.authenticationPolicy == .requiresAuthentication)
        #expect(NotifyLovedOnesIntent.authenticationPolicy == .requiresAuthentication)
        #expect(OpenTripIntent.authenticationPolicy == .requiresAuthentication)
        #expect(OpenBookingIntent.authenticationPolicy == .requiresAuthentication)
    }

    @Test func currencyConversionStillWorksOnALockedPhone() {
        #expect(ConvertCurrencyIntent.authenticationPolicy == .alwaysAllowed)
    }
}
