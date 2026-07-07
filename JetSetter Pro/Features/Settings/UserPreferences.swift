// File: Features/Settings/UserPreferences.swift

import SwiftUI

// MARK: - Color Scheme Preference

enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Distance Unit

enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles      = "miles"
    case kilometers = "kilometers"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miles:      return "Miles (mi)"
        case .kilometers: return "Kilometers (km)"
        }
    }

    var abbreviation: String {
        switch self {
        case .miles:      return "mi"
        case .kilometers: return "km"
        }
    }
}

// MARK: - User Preferences

/// Singleton that persists all user settings across app launches.
/// Passed via `.environment(_:)` from the app root so all views can read/write it.
@MainActor
@Observable
final class UserPreferences {

    static let shared = UserPreferences()

    // MARK: Profile

    var displayName: String         { didSet { save("pref_displayName", displayName) } }
    var email: String               { didSet { save("pref_email", email) } }
    var homeAirport: String         { didSet { save("pref_homeAirport", homeAirport) } }

    // MARK: Travel

    var currency: String            { didSet { save("pref_currency", currency) } }
    var distanceUnit: DistanceUnit  { didSet { save("pref_distanceUnit", distanceUnit.rawValue) } }

    // MARK: Appearance

    var colorSchemePreference: ColorSchemePreference {
        didSet { save("pref_colorScheme", colorSchemePreference.rawValue) }
    }

    var colorScheme: ColorScheme? { colorSchemePreference.colorScheme }

    // MARK: Notifications

    var flightAlertsEnabled: Bool   { didSet { save("pref_flightAlerts", flightAlertsEnabled) } }
    var tripRemindersEnabled: Bool   { didSet { save("pref_tripReminders", tripRemindersEnabled) } }
    var expenseRemindersEnabled: Bool { didSet { save("pref_expenseReminders", expenseRemindersEnabled) } }

    // MARK: IRIS Learning (opt-in; gathers signals to learn the traveler's preferences)

    /// Master switch. When false, no travel signals are recorded at all.
    var learningEnabled: Bool        { didSet { save("pref_learningEnabled", learningEnabled) } }
    /// Per-source controls (only consulted when `learningEnabled` is true).
    var learnFromReceipts: Bool      { didSet { save("pref_learnReceipts", learnFromReceipts) } }
    var learnFromTrips: Bool         { didSet { save("pref_learnTrips", learnFromTrips) } }
    var learnFromCheckIns: Bool      { didSet { save("pref_learnCheckIns", learnFromCheckIns) } }
    /// Tracks whether we've shown the first-run "Let IRIS learn" prompt yet.
    var hasSeenLearningPrompt: Bool  { didSet { save("pref_seenLearningPrompt", hasSeenLearningPrompt) } }

    // MARK: Onboarding

    var hasCompletedOnboarding: Bool { didSet { save("pref_onboarded", hasCompletedOnboarding) } }

    // MARK: - Init (loads persisted values; defaults to dark/executive mode on first launch)

    private init() {
        let d = UserDefaults.standard
        self.displayName           = d.string(forKey: "pref_displayName")  ?? ""
        self.email                 = d.string(forKey: "pref_email")         ?? ""
        self.homeAirport           = d.string(forKey: "pref_homeAirport")   ?? ""
        self.currency              = d.string(forKey: "pref_currency")      ?? "USD"
        self.distanceUnit          = DistanceUnit(rawValue: d.string(forKey: "pref_distanceUnit") ?? "") ?? .miles
        self.colorSchemePreference = ColorSchemePreference(rawValue: d.string(forKey: "pref_colorScheme") ?? "") ?? .dark
        self.flightAlertsEnabled   = d.object(forKey: "pref_flightAlerts")  != nil ? d.bool(forKey: "pref_flightAlerts")   : true
        self.tripRemindersEnabled  = d.object(forKey: "pref_tripReminders") != nil ? d.bool(forKey: "pref_tripReminders")  : true
        self.expenseRemindersEnabled = d.object(forKey: "pref_expenseReminders") != nil ? d.bool(forKey: "pref_expenseReminders") : false
        self.hasCompletedOnboarding = d.bool(forKey: "pref_onboarded")
        // Learning is opt-in: default OFF until the user accepts the first-run prompt.
        self.learningEnabled       = d.bool(forKey: "pref_learningEnabled")
        self.learnFromReceipts     = d.object(forKey: "pref_learnReceipts")  != nil ? d.bool(forKey: "pref_learnReceipts")  : true
        self.learnFromTrips        = d.object(forKey: "pref_learnTrips")     != nil ? d.bool(forKey: "pref_learnTrips")     : true
        self.learnFromCheckIns     = d.object(forKey: "pref_learnCheckIns")  != nil ? d.bool(forKey: "pref_learnCheckIns")  : true
        self.hasSeenLearningPrompt = d.bool(forKey: "pref_seenLearningPrompt")
    }

    // MARK: - Helpers

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased()
    }

    var hasProfile: Bool { !displayName.isEmpty }

    private func save(_ key: String, _ value: String)  { UserDefaults.standard.set(value, forKey: key) }
    private func save(_ key: String, _ value: Bool)    { UserDefaults.standard.set(value, forKey: key) }

    // MARK: - Supported Currencies

    static let supportedCurrencies: [(code: String, name: String)] = [
        ("USD", "US Dollar"), ("EUR", "Euro"), ("GBP", "British Pound"),
        ("JPY", "Japanese Yen"), ("CAD", "Canadian Dollar"), ("AUD", "Australian Dollar"),
        ("CHF", "Swiss Franc"), ("CNY", "Chinese Yuan"), ("HKD", "Hong Kong Dollar"),
        ("SGD", "Singapore Dollar"), ("AED", "UAE Dirham"), ("MXN", "Mexican Peso"),
        ("BRL", "Brazilian Real"), ("INR", "Indian Rupee"), ("NZD", "New Zealand Dollar")
    ]
}
