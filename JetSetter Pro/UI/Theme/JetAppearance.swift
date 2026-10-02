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
/// opt-in automatic Cabin engagement when the device stays without any network path
/// (airplane mode).
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

    /// When true, the UI collapses to the red Cabin palette while the device has had
    /// no network path for `offlineDebounce` (our airplane-mode proxy). Opt-in: an
    /// appearance switch rebuilds the whole view tree (see `JetThemeModifier`), and
    /// `NWPathMonitor` can't tell airplane mode from a dead zone, so defaulting this on
    /// reset every screen whenever a traveler walked into a parking garage.
    @Published var autoCabin: Bool {
        didSet {
            UserDefaults.standard.set(autoCabin, forKey: Self.autoCabinKey)
            recompute()
        }
    }

    /// True once no network path has been available for `offlineDebounce` — our proxy
    /// for airplane mode, matching the design's "Driven by NWPathMonitor (no cellular /
    /// Wi-Fi) or a manual toggle." Debounced, so a blip at the jet bridge doesn't count.
    @Published private(set) var isAirplaneMode: Bool = false

    /// The appearance currently in effect. Drives `\.jet` and the static color mirror.
    @Published private(set) var active: JetAppearance = .executive

    /// How long the device must stay offline before Cabin engages. Reconnecting
    /// cancels the countdown and restores the base appearance immediately.
    static let offlineDebounce: Duration = .seconds(10)

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.jetsetter.pro.cabin.monitor")
    private var offlineDebounceTask: Task<Void, Never>?
    private var hasReceivedFirstPath = false

    private static let selectedKey  = "pref_jetAppearance"
    private static let autoCabinKey = "pref_jetAutoCabin"

    /// The stored auto-Cabin preference. A missing key means the traveler never turned
    /// it on, so it reads as off (`bool(forKey:)` returns false for an absent key).
    static func storedAutoCabinPreference(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: autoCabinKey)
    }

    private init() {
        let d = UserDefaults.standard
        self.selected  = JetAppearance(rawValue: d.string(forKey: Self.selectedKey) ?? "") ?? .executive
        self.autoCabin = Self.storedAutoCabinPreference(in: d)
        self.active    = self.selected
        JetActiveAppearance.current = self.active
        Self.applyUIKitAppearance(for: self.active)
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                // Reference the singleton directly; the store outlives the monitor.
                JetThemeStore.shared.networkPathChanged(satisfied: satisfied)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Applies a network path report. Going offline only counts once it has lasted
    /// `offlineDebounce`; coming back online applies at once. The very first report
    /// (at launch) applies immediately, so someone opening the app already in airplane
    /// mode doesn't see the palette flip ten seconds into using it.
    private func networkPathChanged(satisfied: Bool) {
        offlineDebounceTask?.cancel()
        offlineDebounceTask = nil

        let isFirstReport = !hasReceivedFirstPath
        hasReceivedFirstPath = true

        if satisfied || isFirstReport {
            setAirplaneMode(!satisfied)
            return
        }
        guard !isAirplaneMode else { return }
        offlineDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: JetThemeStore.offlineDebounce)
            guard !Task.isCancelled else { return }
            self?.setAirplaneMode(true)
        }
    }

    private func setAirplaneMode(_ airplane: Bool) {
        guard isAirplaneMode != airplane else { return }
        isAirplaneMode = airplane
        recompute()
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
            // immediately. Most screens still read those statics, so this can't go yet.
            //
            // The rebuild resets every `@State` below this point, pops navigation and
            // closes sheets. That is why switches are kept rare (auto-Cabin is opt-in and
            // debounced; otherwise only a Settings tap), and why launch-once state such as
            // the splash lives above this boundary, in `JetSetter_ProApp`.
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
