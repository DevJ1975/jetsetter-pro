// ContentView.swift

import SwiftUI

struct ContentView: View {

    @Environment(UserPreferences.self) private var preferences
    @Environment(IRISActionRouter.self) private var router
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if preferences.hasCompletedOnboarding {
                    mainTabView
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: preferences.hasCompletedOnboarding)

            if showSplash {
                SplashScreenView(isVisible: $showSplash)
                    .ignoresSafeArea()
                    .zIndex(100)
            }
        }
    }

    // MARK: - Main Tab View

    private var mainTabView: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(IRISActionRouter.Tab.home)

            ItineraryView()
                .tabItem {
                    Label("Itinerary", systemImage: "calendar")
                }
                .tag(IRISActionRouter.Tab.itinerary)

            IRISChatView()
                .tabItem {
                    Label("IRIS", systemImage: "sparkles")
                }
                .tag(IRISActionRouter.Tab.iris)

            ExpenseTrackerView()
                .tabItem {
                    Label("Expenses", systemImage: "chart.bar.fill")
                }
                .tag(IRISActionRouter.Tab.expenses)

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(IRISActionRouter.Tab.more)
        }
        // Tab bar tint is handled globally via UITabBar.appearance() in JetSetter_ProApp
        // Feature screens IRIS asks to open (that aren't tab roots) are presented here.
        .sheet(item: $router.presentedSheet) { sheet in
            routedSheet(sheet)
        }
    }

    // MARK: - Routed Sheets

    @ViewBuilder
    private func routedSheet(_ sheet: IRISActionRouter.Sheet) -> some View {
        switch sheet {
        case .flightTracker:   FlightTrackerView()
        case .documentVault:   DocumentVaultView()
        case .packingList:     PackingListRouterView()
        case .groundTransport: GroundTransportView()
        case .currency:        CurrencyExpenseRouterView()
        }
    }
}

#Preview {
    ContentView()
        .environment(UserPreferences.shared)
        .environmentObject(NotificationManager.shared)
        .environment(IRISActionRouter.shared)
}
