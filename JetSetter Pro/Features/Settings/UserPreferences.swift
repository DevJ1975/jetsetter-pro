// File: Features/Settings/UserPreferences.swift

import SwiftUI
import Combine

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
/// Passed as an @EnvironmentObject from the app root so all views can read/write it.
@MainActor
final class UserPreferences: ObservableObject {

    static let shared = UserPreferences()

    // MARK: Profile

    @Published var displayName: String         { didSet { save("pref_displayName", displayName) } }
    @Published var email: String               { didSet { save("pref_email", email) } }
    @Published var homeAirport: String         { didSet { save("pref_homeAirport", homeAirport) } }

    // MARK: Travel

    @Published var currency: String            { didSet { save("pref_currency", currency) } }
    @Published var distanceUnit: DistanceUnit  { didSet { save("pref_distanceUnit", distanceUnit.rawValue) } }

    // MARK: Appearance

    @Published var colorSchemePreference: ColorSchemePreference {
        didSet { save("pref_colorScheme", colorSchemePreference.rawValue) }
    }

    var colorScheme: ColorScheme? { colorSchemePreference.colorScheme }

    // MARK: Notifications

    @Published var flightAlertsEnabled: Bool   { didSet { save("pref_flightAlerts", flightAlertsEnabled) } }
    @Published var tripRemindersEnabled: Bool   { didSet { save("pref_tripReminders", tripRemindersEnabled) } }
    @Published var expenseRemindersEnabled: Bool { didSet { save("pref_expenseReminders", expenseRemindersEnabled) } }

    // MARK: Onboarding

    @Published var hasCompletedOnboarding: Bool { didSet { save("pref_onboarded", hasCompletedOnboarding) } }

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
