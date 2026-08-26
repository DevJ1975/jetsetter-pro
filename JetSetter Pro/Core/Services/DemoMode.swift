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
    /// (seeded persona for development/pitches).
    ///
    /// PRODUCTION (non-DEBUG / Release / TestFlight) is hard-wired OFF: the
    /// getter is compiled to a constant `false` and the setter is a no-op, so no
    /// release code path — and no persisted UserDefaults value — can ever put the
    /// app into demo mode or reach any mock/seeded data. The mock code below still
    /// compiles; it is simply unreachable at runtime in release.
    static var isOn: Bool {
        get {
            #if DEBUG
            if UserDefaults.standard.object(forKey: storageKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: storageKey)
            #else
            return false
            #endif
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(newValue, forKey: storageKey)
            #else
            // Demo mode is permanently disabled in release builds — no-op.
            _ = newValue
            #endif
        }
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
