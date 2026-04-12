// JetSetter_ProApp.swift

import SwiftUI
import BackgroundTasks

@main
struct JetSetter_ProApp: App {

    @StateObject private var preferences = UserPreferences.shared
    @StateObject private var notifications = NotificationManager.shared
    @StateObject private var subscriptions = SubscriptionManager.shared

    init() {
        configureGlobalAppearance()
        MockDataService.prePopulateIfNeeded()

        // Register the disruption monitoring background task.
        // Must happen before the app finishes launching — init() is the correct place.
        // Also add "com.jetsetter.pro.disruption.poll" to Info.plist under
        // BGTaskSchedulerPermittedIdentifiers, and enable Background Modes →
        // "Background fetch" + "Background processing" in Signing & Capabilities.
        DisruptionMonitorService.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(notifications)
                .environmentObject(subscriptions)
                .preferredColorScheme(preferences.colorScheme)
                .task {
                    await notifications.requestAuthorization()
                    await subscriptions.refreshEntitlements()
                    // Schedule the first disruption poll when the app comes to the foreground.
                    DisruptionMonitorService.shared.scheduleNextPoll()
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
