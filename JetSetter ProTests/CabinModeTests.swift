// File: JetSetter ProTests/CabinModeTests.swift
//
// Auto-Cabin rebuilds the whole view tree when it engages, so it must be
// opt-in and must not react to a momentary network blip.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct CabinModeTests {

    /// Defect: auto-Cabin defaulted to on and engaged on any lost network path,
    /// so walking into a dead zone reset every screen and replayed the splash.
    @Test func autoCabinIsOffWhenNoPreferenceIsStored() throws {
        let suiteName = "CabinModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(JetThemeStore.storedAutoCabinPreference(in: defaults) == false)
    }

    @Test func autoCabinStaysOnOnceTheTravelerTurnsItOn() throws {
        let suiteName = "CabinModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "pref_jetAutoCabin")
        #expect(JetThemeStore.storedAutoCabinPreference(in: defaults) == true)
    }

    @Test func goingOfflineMustLastTenSecondsBeforeCabinEngages() {
        #expect(JetThemeStore.offlineDebounce == .seconds(10))
    }
}
