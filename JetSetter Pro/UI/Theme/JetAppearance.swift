// File: UI/Theme/JetAppearance.swift
// JetSetter Pro — runtime appearance system (Executive · Cabin · Heritage)
//
// Implements §02–§05 of the "JetSetter Pro · iOS — Icon & Material System"
// design spec. The original palette lived in a static `JetsetterTheme` enum that
// could only switch on light/dark. This file layers a runtime appearance on top so
// the whole UI can collapse to the red "Cabin" night palette in airplane mode, or
// adopt the optional leather-and-gold "Heritage" appearance — without every screen
// needing per-mode code.
//
// New screens read the active palette from the environment:
//     @Environment(\.jet) private var jet
//     Text("Gate B12").foregroundStyle(jet.textPrimary)
//
// Existing screens that read `JetsetterTheme.Colors.*` keep working — those
// accessors now resolve through the active appearance too (see JetsetterTheme.swift).

import SwiftUI
import Network
import Combine

// MARK: - Appearance

/// The three first-class appearances from the design system.
enum JetAppearance: String, CaseIterable, Identifiable {
    /// Default sky-blue-on-navy. Also drives the adaptive light palette.
    case executive
    /// All-red night mode. Auto-engages in airplane mode to preserve night vision —
    /// semantic state reads by *brightness*, not hue (danger brightest → success dimmest).
    case cabin
    /// Optional premium leather & gold appearance.
    case heritage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .executive: return "Executive"
        case .cabin:     return "Cabin"
        case .heritage:  return "Heritage"
        }
    }

    var systemImage: String {
        switch self {
        case .executive: return "airplane"
        case .cabin:     return "airplane.circle.fill"
        case .heritage:  return "crown.fill"
        }
    }
}

// MARK: - Active appearance mirror

/// Plain (non-isolated) mirror of the active appearance.
///
/// `JetsetterTheme.Colors.*` are non-isolated static accessors read from countless
/// SwiftUI bodies; routing them through the `@MainActor` `JetThemeStore` would force an
/// actor hop on every color read. Instead `JetThemeStore` mirrors its `active` value
/// here (always written on the main thread) and the static accessors read it directly.
enum JetActiveAppearance {
    nonisolated(unsafe) static var current: JetAppearance = .executive
}

// MARK: - Theme store

/// Owns the active appearance: a user-selected base (Executive / Heritage) plus
/// automatic Cabin engagement when the device loses all network paths (airplane mode).
@MainActor
final class JetThemeStore: ObservableObject {

    static let shared = JetThemeStore()

    /// The user's chosen base appearance. Cabin is normally automatic, so the Settings
    /// selector offers Executive / Heritage; Cabin is driven by `autoCabin` + airplane mode.
    @Published var selected: JetAppearance {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.selectedKey)
            recompute()
        }
    }

    /// When true (default), the UI collapses to the red Cabin palette while the device
    /// has no network path (airplane mode). Disable to keep the chosen base appearance aloft.
    @Published var autoCabin: Bool {
        didSet {
            UserDefaults.standard.set(autoCabin, forKey: Self.autoCabinKey)
            recompute()
        }
    }

    /// True when no network path is available — our proxy for airplane mode, matching the
    /// design's "Driven by NWPathMonitor (no cellular / Wi-Fi) or a manual toggle."
    @Published private(set) var isAirplaneMode: Bool = false

    /// The appearance currently in effect. Drives `\.jet` and the static color mirror.
    @Published private(set) var active: JetAppearance = .executive

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.jetsetter.pro.cabin.monitor")

    private static let selectedKey  = "pref_jetAppearance"
    private static let autoCabinKey = "pref_jetAutoCabin"

    private init() {
        let d = UserDefaults.standard
        self.selected  = JetAppearance(rawValue: d.string(forKey: Self.selectedKey) ?? "") ?? .executive
        self.autoCabin = d.object(forKey: Self.autoCabinKey) != nil ? d.bool(forKey: Self.autoCabinKey) : true
        self.active    = self.selected
        JetActiveAppearance.current = self.active
        Self.applyUIKitAppearance(for: self.active)
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            let airplane = path.status != .satisfied
            Task { @MainActor in
                // Reference the singleton directly; the store outlives the monitor.
                let store = JetThemeStore.shared
                guard store.isAirplaneMode != airplane else { return }
                store.isAirplaneMode = airplane
                store.recompute()
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Manually toggle the chosen base appearance — used by the Settings selector.
    func select(_ appearance: JetAppearance) {
        // Cabin isn't a base choice; it's automatic. Treat an explicit Cabin tap as
        // "force Executive but let auto-cabin handle the air."
        selected = (appearance == .cabin) ? .executive : appearance
    }

    private func recompute() {
        let next: JetAppearance = (autoCabin && isAirplaneMode) ? .cabin : selected
        guard next != active else { return }
        active = next
        JetActiveAppearance.current = next
        Self.applyUIKitAppearance(for: next)
    }

    // MARK: UIKit chrome

    /// Re-tints the shared navigation / tab bars so the accent matches the active
    /// appearance. SwiftUI views recolor via `\.jet`; the UIKit appearance proxies are
    /// global state that must be re-applied imperatively when the appearance changes.
    static func applyUIKitAppearance(for appearance: JetAppearance) {
        let accent = UIColor(JetsetterTheme.Colors.accentValue(for: appearance))
        let muted  = UIColor(JetsetterTheme.Colors.textSecondaryValue(for: appearance))

        UINavigationBar.appearance().tintColor = accent

        let item = UITabBarItemAppearance()
        item.selected.iconColor = accent
        item.selected.titleTextAttributes = [.foregroundColor: accent,
                                              .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
        item.normal.iconColor = muted
        item.normal.titleTextAttributes = [.foregroundColor: muted,
                                            .font: UIFont.systemFont(ofSize: 10, weight: .regular)]

        // Mutate the existing (reference-type) appearance in place to preserve the
        // configured blur / separator, then re-assign so the change takes effect.
        let tab = UITabBar.appearance().standardAppearance
        tab.stackedLayoutAppearance       = item
        tab.inlineLayoutAppearance        = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance   = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

// MARK: - Palette (environment-facing)

/// A lightweight snapshot of the active palette, surfaced through `\.jet`. Color tokens
/// delegate to the appearance-aware `JetsetterTheme.Colors`, so the environment value and
/// the static accessors never drift apart.
struct JetPalette {
    let appearance: JetAppearance

    var isCabin: Bool    { appearance == .cabin }
    var isHeritage: Bool { appearance == .heritage }
    /// True for the always-dark appearances (Cabin, Heritage). Executive follows the
    /// system color scheme, which a palette can't see — callers needing Executive's
    /// dark state should read `@Environment(\.colorScheme)`. Drives glow choices.
    var isDark: Bool     { appearance != .executive }

    var background: Color       { JetsetterTheme.Colors.backgroundValue(for: appearance) }
    var surface: Color          { JetsetterTheme.Colors.surfaceValue(for: appearance) }
    var surfaceElevated: Color  { JetsetterTheme.Colors.surfaceElevatedValue(for: appearance) }
    var primary: Color          { JetsetterTheme.Colors.primaryValue(for: appearance) }
    var accent: Color           { JetsetterTheme.Colors.accentValue(for: appearance) }
    var blue: Color             { JetsetterTheme.Colors.blueValue(for: appearance) }
    var success: Color          { JetsetterTheme.Colors.successValue(for: appearance) }
    var warning: Color          { JetsetterTheme.Colors.warningValue(for: appearance) }
    var danger: Color           { JetsetterTheme.Colors.dangerValue(for: appearance) }
    var textPrimary: Color      { JetsetterTheme.Colors.textPrimaryValue(for: appearance) }
    var textSecondary: Color    { JetsetterTheme.Colors.textSecondaryValue(for: appearance) }
    var separator: Color        { JetsetterTheme.Colors.separatorValue(for: appearance) }

    var accentGradient: LinearGradient { JetsetterTheme.Colors.accentGradientValue(for: appearance) }
    var heroGradient: LinearGradient   { JetsetterTheme.Colors.heroGradientValue(for: appearance) }
    var borderGradient: LinearGradient { JetsetterTheme.Colors.borderGradientValue(for: appearance) }

    static let executive = JetPalette(appearance: .executive)
}

private struct JetPaletteKey: EnvironmentKey {
    static let defaultValue = JetPalette.executive
}

extension EnvironmentValues {
    /// The active JetSetter palette. Read it in new screens: `@Environment(\.jet) var jet`.
    var jet: JetPalette {
        get { self[JetPaletteKey.self] }
        set { self[JetPaletteKey.self] = newValue }
    }
}

// MARK: - Root modifier

private struct JetThemeModifier: ViewModifier {
    @ObservedObject private var store = JetThemeStore.shared

    func body(content: Content) -> some View {
        content
            .environment(\.jet, JetPalette(appearance: store.active))
            // Force the tree to rebuild when the appearance switches so screens that read
            // the static `JetsetterTheme.Colors.*` accessors (rather than `\.jet`) recolor
            // immediately. Appearance changes are rare (airplane-mode toggle / a Settings
            // tap), so the rebuild cost is acceptable.
            //
            // Note: this swaps view identity, so the old and new trees share no continuous
            // view to interpolate — an `.animation(value: store.active)` here would be dead
            // (it can't cross-fade an identity replacement in place). The recolor is
            // therefore intentionally instantaneous.
            .id(store.active)
    }
}

extension View {
    /// Installs the JetSetter appearance system: injects `\.jet` and recolors on switch.
    /// Apply once at the app root.
    func jetTheme() -> some View { modifier(JetThemeModifier()) }
}
