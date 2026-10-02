// File: ContentView.swift
//
// The app's root: onboarding, the launch splash, and the tab view with the
// routed-sheet host that `AppRouter` drives.
//
// The tabs are Home, Itinerary, Wallet, Expenses and More. Wallet replaced
// the Siri tab (October 2026): at the gate the boarding pass is the thing a
// traveler reaches for, and it was three taps deep in More. The Siri guide
// still lives in More, and a routed request (`.assistant`) shows it as a sheet.
//
// `.sidebarAdaptable` lets the tab bar become a sidebar where the system
// offers one for the available width (the foldable iPhone Ultra's inner
// display). Nothing here checks the device model or orientation.

import SwiftUI

struct ContentView: View {

    @Environment(UserPreferences.self) private var preferences
    @Environment(AppRouter.self) private var router
    /// Owned by `JetSetter_ProApp`, above the `.jetTheme()` boundary. An appearance
    /// switch swaps this view's identity and resets its `@State`; when the flag lived
    /// here, every network drop with auto-Cabin on replayed the launch splash.
    @Binding var showSplash: Bool

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
            Tab("Home", systemImage: "house.fill", value: AppRouter.Tab.home) {
                HomeView()
            }
            Tab("Itinerary", systemImage: "calendar", value: AppRouter.Tab.itinerary) {
                ItineraryView()
            }
            Tab("Wallet", systemImage: "wallet.pass.fill", value: AppRouter.Tab.wallet) {
                WalletTab()
            }
            Tab("Expenses", systemImage: "chart.bar.fill", value: AppRouter.Tab.expenses) {
                ExpenseTrackerView()
            }
            Tab("More", systemImage: "ellipsis.circle.fill", value: AppRouter.Tab.more) {
                MoreView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Tab bar tint is handled globally via UITabBar.appearance() in JetSetter_ProApp
        // Feature screens the app asks to open (that aren't tab roots) are presented here.
        .sheet(item: $router.presentedSheet) { sheet in
            routedSheet(sheet)
        }
    }

    // MARK: - Routed Sheets

    /// None of these screens carries its own NavigationStack (most are also
    /// pushed from More, where a second stack doubled the bars), so each sheet
    /// gets its one stack, title bar and Done button from `.inSheetNavigation()`.
    /// `NewTripSheet` is a form with its own stack and Cancel / Save.
    @ViewBuilder
    private func routedSheet(_ sheet: AppRouter.Sheet) -> some View {
        switch sheet {
        case .flightTracker:   FlightTrackerView().inSheetNavigation()
        case .documentVault:   DocumentVaultView().inSheetNavigation()
        case .packingList:     PackingListRouterView().inSheetNavigation()
        case .groundTransport: GroundTransportView().inSheetNavigation()
        case .currency:        CurrencyExpenseRouterView().inSheetNavigation()
        case .siriGuide:       SiriAssistantView().inSheetNavigation()
        case .newTrip:         NewTripSheet()
        }
    }
}

// MARK: - Wallet tab

/// Hosts the Travel Wallet as a tab and shows a specific pass when the router
/// asks (Home's "Boarding pass" button, the Live Activity, a notification's
/// "View boarding pass", `jetsetterpro://wallet/pass/<id>`).
///
/// The request arrives as a pending action consumed in `.task`, so it survives
/// a cold launch. Matching uses `BoardingPassMatcher` against a freshly loaded
/// wallet: the list's own view model may predate a pass saved a minute ago at
/// check-in. With no match the traveler simply sees the wallet list.
private struct WalletTab: View {
    @Environment(AppRouter.self) private var router
    @State private var presentedPass: PresentedPass?

    /// The pass on screen plus the view model it was found in, which
    /// `BoardingPassDetailView` reads from.
    private struct PresentedPass: Identifiable {
        let item: WalletItem
        let store: WalletViewModel
        var id: UUID { item.id }
    }

    var body: some View {
        // The tab's one stack. TravelWalletView has none of its own because
        // More pushes it too, and a second stack there doubled the bars.
        NavigationStack {
            TravelWalletView()
        }
        .sheet(item: $presentedPass) { pass in
            NavigationStack {
                BoardingPassDetailView(item: pass.item, viewModel: pass.store)
            }
        }
        .task { await showRequestedPass() }
        .onChange(of: router.pendingAction) { _, _ in
            Task { await showRequestedPass() }
        }
        .onChange(of: router.modalDismissalRequest) { _, _ in
            presentedPass = nil
        }
    }

    private func showRequestedPass() async {
        guard let action = router.pendingAction else { return }
        let match: (WalletItem, WalletViewModel)?
        switch action {
        case .showWalletPass(let id):
            router.consume(action)
            let store = await loadedWallet()
            match = store.items.first { $0.id == id }.map { ($0, store) }
        case .showBoardingPass(let flightNumber, let departure):
            router.consume(action)
            let store = await loadedWallet()
            match = BoardingPassMatcher.match(in: store.items, flightNumber: flightNumber, departure: departure)
                .map { ($0, store) }
        default:
            return   // Not the wallet's to handle.
        }
        guard let match else { return }
        let (item, store) = match

        // A boarding pass gets the full-screen pass; anything else stays on the
        // list, where its own detail sheet is one tap away.
        guard item.itemType == .boardingPass else { return }
        try? await Task.sleep(for: router.presentationDelay())
        presentedPass = PresentedPass(item: item, store: store)
    }

    private func loadedWallet() async -> WalletViewModel {
        let store = WalletViewModel()
        await store.load()
        return store
    }
}

// MARK: - New trip

/// The Add Trip form for `jetsetterpro://trip/new` (the Next Trip widget's
/// empty state). Saves through `ItineraryViewModel.addTrip`, the same path as
/// the Itinerary tab's "+", so the trip lands in the one store and the
/// notification permission is asked at the same moment.
///
/// It mirrors the Itinerary tab's own form, which is private to that screen.
/// When the Itinerary screen next changes, it can consume a routed request
/// itself and this copy can go.
private struct NewTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var itinerary = ItineraryViewModel()
    @State private var name = ""
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Info") {
                    TextField("Trip name (e.g. Tokyo Spring Trip)", text: $name)
                    TextField("Destination (e.g. Tokyo, Japan)", text: $destination)
                }
                Section("Dates") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? JetsetterTheme.Colors.accent : .secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        itinerary.addTrip(Trip(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: max(endDate, startDate)
        ))
        dismiss()
    }
}

#Preview {
    ContentView(showSplash: .constant(false))
        .environment(UserPreferences.shared)
        .environmentObject(NotificationManager.shared)
        .environment(AppRouter.shared)
}
