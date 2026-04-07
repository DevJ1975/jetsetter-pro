// JetSetter_ProApp.swift

import SwiftUI

@main
struct JetSetter_ProApp: App {

    @StateObject private var preferences = UserPreferences.shared
    @StateObject private var notifications = NotificationManager.shared

    init() {
        configureGlobalAppearance()
        MockDataService.prePopulateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(notifications)
                .preferredColorScheme(preferences.colorScheme)
                .task {
                    await notifications.requestAuthorization()
                }
        }
    }

    // MARK: - Global UIAppearance
    // Sets the premium gold + glass aesthetic app-wide before any view renders.

    private func configureGlobalAppearance() {
        // Signature gold tint
        let gold  = UIColor(red: 201/255, green: 168/255, blue: 76/255,  alpha: 1) // #C9A84C
        let muted = UIColor(red: 139/255, green: 146/255, blue: 168/255, alpha: 1) // #8B92A8

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
        UINavigationBar.appearance().tintColor             = gold  // back chevrons, buttons

        // ── Tab Bar ─────────────────────────────────────────────────────────
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tab.shadowColor = .clear

        // Hair-line top separator in dark mode
        let separator = UIImage.solidColor(color: UIColor(red: 201/255, green: 168/255, blue: 76/255, alpha: 0.18),
                                           size: CGSize(width: 1, height: 0.5))
        tab.shadowImage = separator

        let item = UITabBarItemAppearance()
        item.selected.iconColor = gold
        item.selected.titleTextAttributes = [.foregroundColor: gold,
                                              .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
        item.normal.iconColor = muted
        item.normal.titleTextAttributes  = [.foregroundColor: muted,
                                             .font: UIFont.systemFont(ofSize: 10, weight: .regular)]

        tab.stackedLayoutAppearance      = item
        tab.inlineLayoutAppearance       = item
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
