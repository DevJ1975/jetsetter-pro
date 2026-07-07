// File: Core/Services/DemoMode.swift
//
// Runtime demo-mode switch (IOS_PARITY_NOTES.md §7.2). Mirrors Android's
// More → Presentation toggle plus the alpha-only Home "DEMO" chip. Enabling it
// reseeds the pristine Jordan Ellis / Atlanta persona, marks onboarding
// complete, fills blank profile fields, and arms the scripted ~25s DL 1423
// disruption push so a presenter gets the "traveler notified" beat on cue.

import Foundation

enum DemoMode {

    static let storageKey = "demoMode"

    /// The single source of truth for demo (on) vs beta (off) mode. Drives
    /// `MockDataService.isEnabled`, so flipping it switches every service call
    /// site between seeded mock data and live/real behavior at runtime.
    ///
    /// Default when the user has never chosen: DEBUG builds start in demo mode
    /// (seeded persona for development/pitches); Release/TestFlight builds start
    /// in beta mode (live services, real/empty states).
    static var isOn: Bool {
        get {
            if UserDefaults.standard.object(forKey: storageKey) == nil {
                #if DEBUG
                return true
                #else
                return false
                #endif
            }
            return UserDefaults.standard.bool(forKey: storageKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    /// Turns demo mode on and seeds the pristine dataset.
    @MainActor
    static func enable() async {
        isOn = true
        seedPristineData()
        UserPreferences.shared.hasCompletedOnboarding = true
        await NotificationManager.shared.scheduleDemoDisruptionPush()
        NotificationCenter.default.post(name: .jetSetterDemoDataReset, object: nil)
    }

    /// Turns demo mode off. Seeded data is left in place; "Reset" clears it.
    static func disable() {
        isOn = false
    }

    /// Restores the pristine seeded dataset without touching the toggle — the
    /// "Reset demo data" action available between run-throughs.
    @MainActor
    static func resetData() async {
        seedPristineData()
        await NotificationManager.shared.scheduleDemoDisruptionPush()
        NotificationCenter.default.post(name: .jetSetterDemoDataReset, object: nil)
    }

    /// Wipes and re-seeds trips/expenses/bags/wallet/loyalty/disruption to the
    /// persona. `DemoSeeder.reset()` clears the populated flags so the guarded
    /// `prePopulateIfNeeded()` re-runs and re-invokes `DemoSeeder.seedAll()`.
    private static func seedPristineData() {
        DemoSeeder.reset()
        MockDataService.prePopulateIfNeeded()
    }
}

extension Notification.Name {
    /// Posted after demo data is (re)seeded so any visible list can reload.
    static let jetSetterDemoDataReset = Notification.Name("jetSetterDemoDataReset")
}
