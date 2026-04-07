// ContentView.swift

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var preferences: UserPreferences
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
        TabView {
            FlightTrackerView()
                .tabItem {
                    Label("Flights", systemImage: "airplane")
                }

            ItineraryView()
                .tabItem {
                    Label("Itinerary", systemImage: "calendar")
                }

            AssistantView()
                .tabItem {
                    Label("Assistant", systemImage: "sparkles")
                }

            ExpenseTrackerView()
                .tabItem {
                    Label("Expenses", systemImage: "chart.bar.fill")
                }

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        // Tab bar tint is handled globally via UITabBar.appearance() in JetSetter_ProApp
    }
}

#Preview {
    ContentView()
        .environmentObject(UserPreferences.shared)
        .environmentObject(NotificationManager.shared)
}
