// File: JetSetter ProTests/ThemeTests.swift
// Unit tests for the runtime appearance system (JetAppearance / JetThemeStore / JetPalette).
// These mirror the behavior validated interactively during the beta-prep debug pass.

import Testing
import SwiftUI
@testable import JetSetter_Pro

@MainActor
struct ThemeTests {

    // MARK: - JetAppearance enum integrity

    @Test func appearanceHasThreeCases() {
        #expect(JetAppearance.allCases.count == 3)
    }

    @Test func appearanceDisplayNames() {
        #expect(JetAppearance.executive.displayName == "Executive")
        #expect(JetAppearance.cabin.displayName == "Cabin")
        #expect(JetAppearance.heritage.displayName == "Heritage")
    }

    @Test func appearanceSystemImages() {
        #expect(JetAppearance.executive.systemImage == "airplane")
        #expect(JetAppearance.cabin.systemImage == "airplane.circle.fill")
        #expect(JetAppearance.heritage.systemImage == "crown.fill")
    }

    @Test func appearanceIdMatchesRawValue() {
        for appearance in JetAppearance.allCases {
            #expect(appearance.id == appearance.rawValue)
        }
    }

    // MARK: - Selection behavior

    /// Cabin is automatic (airplane mode) only — an explicit Cabin selection must
    /// coerce to Executive so the base appearance is never manually pinned to Cabin.
    @Test func selectingCabinCoercesToExecutive() {
        let store = JetThemeStore.shared
        store.select(.cabin)
        #expect(store.selected == .executive)
        #expect(store.active == .executive)
        store.select(.executive) // restore
    }

    /// Selecting a real base appearance propagates to both `selected` and (when not
    /// in airplane mode) `active`.
    @Test func selectingHeritageActivatesIt() {
        let store = JetThemeStore.shared
        store.select(.heritage)
        #expect(store.selected == .heritage)
        #expect(store.active == .heritage)
        store.select(.executive) // restore
    }

    @Test func selectionPersistsToUserDefaults() {
        let store = JetThemeStore.shared
        store.select(.heritage)
        #expect(UserDefaults.standard.string(forKey: "pref_jetAppearance") == "heritage")
        store.select(.executive)
        #expect(UserDefaults.standard.string(forKey: "pref_jetAppearance") == "executive")
    }

    // MARK: - Palette delegation

    /// `JetPalette` must resolve to the same colors as the appearance-aware
    /// `JetsetterTheme.Colors.*Value(for:)` accessors — they must never drift apart.
    @Test func paletteDelegatesToThemeColors() {
        for appearance in JetAppearance.allCases {
            let palette = JetPalette(appearance: appearance)
            #expect(UIColor(palette.accent)
                    == UIColor(JetsetterTheme.Colors.accentValue(for: appearance)))
            #expect(UIColor(palette.background)
                    == UIColor(JetsetterTheme.Colors.backgroundValue(for: appearance)))
            #expect(UIColor(palette.textPrimary)
                    == UIColor(JetsetterTheme.Colors.textPrimaryValue(for: appearance)))
        }
    }

    // MARK: - isDark

    /// Cabin and Heritage are always dark-on; Executive follows the system scheme
    /// (which a palette can't see) and therefore reports false.
    @Test func isDarkOnlyForAlwaysDarkAppearances() {
        #expect(JetPalette(appearance: .executive).isDark == false)
        #expect(JetPalette(appearance: .cabin).isDark == true)
        #expect(JetPalette(appearance: .heritage).isDark == true)
    }
}
