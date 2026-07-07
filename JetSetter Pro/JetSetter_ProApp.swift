// JetSetter_ProApp.swift

import SwiftUI
import BackgroundTasks

@main
struct JetSetter_ProApp: App {

    @State private var preferences = UserPreferences.shared
    @StateObject private var notifications = NotificationManager.shared
    @State private var subscriptions = SubscriptionManager.shared
    @StateObject private var theme = JetThemeStore.shared
    @State private var router = IRISActionRouter.shared

    init() {
        configureGlobalAppearance()

        // Establish the default app mode on first launch (DEBUG → demo,
        // Release/TestFlight → beta) so the persisted toggle, @AppStorage
        // bindings, and MockDataService.isEnabled all agree from the first frame.
        if UserDefaults.standard.object(forKey: DemoMode.storageKey) == nil {
            #if DEBUG
            DemoMode.isOn = true
            #else
            DemoMode.isOn = false
            #endif
        }

        MockDataService.prePopulateIfNeeded()

        // Route notification taps to in-app screens. Must be assigned before any
        // notification can fire — init() is the correct place. Without this,
        // tapping a disruption push just opens Home regardless of payload.
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        // Register the disruption monitoring background task.
        // Must happen before the app finishes launching — init() is the correct place.
        // Also add "com.jetsetter.pro.disruption.poll" to Info.plist under
        // BGTaskSchedulerPermittedIdentifiers, and enable Background Modes →
        // "Background fetch" + "Background processing" in Signing & Capabilities.
        DisruptionMonitorService.shared.registerBackgroundTask()

        // Start the watch connectivity session. Safe to call even when no
        // watch is paired — it's a no-op until pairing completes.
        WatchConnectivityService.shared.activate()

        // DEMO MODE (DEBUG only): auto-unlock Pro so every gated feature is
        // accessible for the demo. Release builds enforce real StoreKit
        // entitlements via SubscriptionManager.refreshEntitlements().
        #if DEBUG
        Task { @MainActor in
            SubscriptionManager.shared.unlockForTesting()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(preferences)
                .environmentObject(notifications)
                .environment(subscriptions)
                .environmentObject(theme)
                .environment(router)
                .jetTheme()
                .preferredColorScheme(preferences.colorScheme)
                .task {
                    await notifications.requestAuthorization()
                    // Proactively schedule trip/flight reminders from the current
                    // itinerary, and keep them in sync as trips change.
                    TravelNotificationScheduler.shared.startObservingTripChanges()
                    await TravelNotificationScheduler.shared.rescheduleAll()
                    await subscriptions.refreshEntitlements()
                    // Anonymous-first Supabase sign-in so cross-device sync works
                    // without forcing a login (IOS_PARITY_NOTES.md §3). No-op if a
                    // session already exists; silently skipped if unconfigured.
                    try? await SupabaseService.shared.ensureSignedIn()
                    // Schedule the first disruption poll when the app comes to the foreground.
                    DisruptionMonitorService.shared.scheduleNextPoll()
                    // Pre-cache the offline kit when the soonest trip enters its
                    // 48h-before window, so it's populated without the user having
                    // to open the OfflineKit screen and tap Refresh.
                    await OfflineKitService.shared.cacheUpcomingTripIfWithinWindow()
                }
        }
    }

    // MARK: - Global UIAppearance
    // Sets the premium blue glass aesthetic app-wide before any view renders.

    private func configureGlobalAppearance() {
        // App accent blue — matches JetsetterTheme.Colors.accent (#3B9EF0)
        let accent = UIColor(red: 59/255,  green: 158/255, blue: 240/255, alpha: 1) // #3B9EF0
        let muted  = UIColor(red: 139/255, green: 146/255, blue: 168/255, alpha: 1) // #8B92A8

        // ── Navigation Bar ──────────────────────────────────────────────────
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        nav.shadowColor = .clear
        // System-adaptive title colors (white in dark, near-black in light)
        nav.titleTextAttributes      = [.foregroundColor: UIColor.label,
                                         .font: UIFont.systemFont(ofSize: 17, weight: .semibold)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.label,
                                         .font: UIFont.systemFont(ofSize: 34, weight: .bold)]

        UINavigationBar.appearance().standardAppearance    = nav
        UINavigationBar.appearance().scrollEdgeAppearance  = nav
        UINavigationBar.appearance().compactAppearance     = nav
        UINavigationBar.appearance().tintColor             = accent  // back chevrons, buttons

        // ── Tab Bar ─────────────────────────────────────────────────────────
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tab.shadowColor = .clear

        // Hair-line top separator — blue tint
        let separator = UIImage.solidColor(
            color: UIColor(red: 59/255, green: 158/255, blue: 240/255, alpha: 0.20),
            size: CGSize(width: 1, height: 0.5)
        )
        tab.shadowImage = separator

        let item = UITabBarItemAppearance()
        item.selected.iconColor = accent
        item.selected.titleTextAttributes = [.foregroundColor: accent,
                                              .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
        item.normal.iconColor = muted
        item.normal.titleTextAttributes  = [.foregroundColor: muted,
                                             .font: UIFont.systemFont(ofSize: 10, weight: .regular)]

        tab.stackedLayoutAppearance       = item
        tab.inlineLayoutAppearance        = item
        tab.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance   = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

// MARK: - UIImage solid colour helper

private extension UIImage {
    static func solidColor(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
