// File: Features/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {

    @Environment(UserPreferences.self) private var preferences
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @EnvironmentObject private var theme: JetThemeStore

    @State private var settingsWebURL: URL?   // in-app web sheet (Privacy/Terms, §7.7)

    // Edit profile
    @State private var editName     = ""
    @State private var editAirport  = ""
    @State private var isEditingProfile = false


    // Alert
    @State private var showClearDataAlert = false

    // Subscription
    @State private var showPaywall = false

    #if DEMO_ENABLED
    // Demo mode (Debug and Beta builds only)
    @State private var demoIsOn = DemoMode.isOn
    @State private var isSeedingDemo = false
    @State private var showDemoResetAlert = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileCard
                    subscriptionSection
                    appearanceSection
                    travelSection
                    notificationsSection
                    travelContactsSection
                    dataSection
                    // Sample data for demos. Compiled into Debug and Beta only —
                    // Release, which is what App Store builds archive from, does
                    // not define DEMO_ENABLED.
                    #if DEMO_ENABLED
                    demoSection
                    #endif
                    // Developer tools (e.g. evaluation Pro unlock) ship DEBUG-only.
                    #if DEBUG
                    developerSection
                    #endif
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .inAppWeb(url: $settingsWebURL)
            .sheet(isPresented: $isEditingProfile) {
                EditProfileSheet(preferences: preferences)
            }
            .sheet(isPresented: $showPaywall) {
                SubscriptionPaywallView()
                    .environment(subscriptionManager)
            }
            .alert("Clear Local Data?", isPresented: $showClearDataAlert) {
                Button("Clear All", role: .destructive) { clearLocalData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all locally saved travel data (trips, expenses, bags, documents, and more). This cannot be undone.")
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.goldGradient)
                    .frame(width: 64, height: 64)
                Text(preferences.hasProfile ? preferences.initials : "JS")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#0A0A10"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(preferences.hasProfile ? preferences.displayName : "JetSetter Traveler")
                    .font(.title3).bold()
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                HStack(spacing: 6) {
                    if !preferences.homeAirport.isEmpty {
                        GoldTag(text: preferences.homeAirport, icon: "airplane")
                    }
                    GoldTag(text: preferences.currency)
                }
            }

            Spacer()

            Button {
                editName    = preferences.displayName
                editAirport = preferences.homeAirport
                isEditingProfile = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
        }
        .padding(20)
        .jetCard()
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        settingsSection(title: "JETSETTER PRO", icon: "crown.fill") {
            if subscriptionManager.isProSubscriber {
                // Active subscriber state
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(JetsetterTheme.Colors.success)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pro Subscription Active")
                            .font(.subheadline).bold()
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        Text("Thank you for subscribing!")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                    Spacer()
                    GoldTag(text: "PRO", icon: "crown.fill")
                }
            } else {
                // Upgrade CTA state
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Pro")
                                .font(.subheadline).bold()
                                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                            Text("Unlock all features · In-app purchase")
                                .font(.caption)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }

                    Button { showPaywall = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.caption).bold()
                            Text("View Plans")
                                .font(.subheadline).bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(JetsetterTheme.Colors.accent)
                        .foregroundStyle(Color(hex: "#0A0A10"))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        @Bindable var preferences = preferences
        return settingsSection(title: "APPEARANCE", icon: "paintbrush.fill") {
            VStack(spacing: 0) {
                settingsLabel("Color Scheme", icon: "circle.lefthalf.filled",
                              value: preferences.colorSchemePreference.displayName)

                HStack(spacing: 8) {
                    ForEach(ColorSchemePreference.allCases) { pref in
                        schemeChip(pref)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 4)

                settingsDivider()

                // Theme appearance — Executive (default) or the premium Heritage binder.
                // Cabin (red night) isn't a manual base choice; it engages automatically
                // in airplane mode via the toggle below.
                settingsLabel("Theme", icon: "sparkles",
                              value: theme.active.displayName)

                HStack(spacing: 8) {
                    appearanceChip(.executive)
                    appearanceChip(.heritage)
                }
                .padding(.top, 10)
                .padding(.horizontal, 4)

                settingsDivider()

                Toggle(isOn: $theme.autoCabin) {
                    settingsLabel("Cabin Mode in Airplane Mode", icon: "airplane.circle.fill")
                }
                .tint(JetsetterTheme.Colors.accent)

                Text(theme.active == .cabin
                     ? "Cabin mode is active — the UI is red to protect night vision."
                     : "Switches the whole UI to a low-disturbance red while your device is offline in flight.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                settingsDivider()

                // the app Learning — opt-in. the app learns the traveler's seat/airline/spend
                // patterns from their own activity, fully on-device. Master switch plus
                // per-source controls; "What the app Has Learned" shows & clears the profile.
                Toggle(isOn: $preferences.learningEnabled) {
                    settingsLabel("Learn From My Activity", icon: "brain.head.profile")
                }
                .tint(JetsetterTheme.Colors.accent)
                .onChange(of: preferences.learningEnabled) { _, _ in
                    TravelProfileStore.shared.recompute()
                }

                // Per-source controls stay visible even when the master is off, so a
                // privacy-conscious user can always audit exactly what the app is allowed
                // to learn. When the master is off they're greyed out (disabled), and
                // "What the app Has Learned" is hidden since there's nothing to inspect.
                Group {
                    Toggle(isOn: $preferences.learnFromCheckIns) {
                        settingsLabel("Learn From Seats & Check-ins", icon: "chair.fill")
                    }
                    Toggle(isOn: $preferences.learnFromReceipts) {
                        settingsLabel("Learn From Receipts & Expenses", icon: "doc.text.viewfinder")
                    }
                    Toggle(isOn: $preferences.learnFromTrips) {
                        settingsLabel("Learn From Trips & Flights", icon: "airplane")
                    }
                }
                .tint(JetsetterTheme.Colors.accent)
                .disabled(!preferences.learningEnabled)
                .opacity(preferences.learningEnabled ? 1 : 0.55)

                if preferences.learningEnabled {
                    NavigationLink {
                        LearnedProfileView()
                    } label: {
                        settingsLabel("What JetSetter Has Learned", icon: "sparkles.rectangle.stack")
                    }
                    .padding(.top, 4)
                }

                Text("JetSetter Pro learns only on this iPhone, from your own activity — never shared. Turn off any source, or wipe everything with Clear Local Data.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
    }

    private func appearanceChip(_ appearance: JetAppearance) -> some View {
        let selected = theme.selected == appearance
        return Button { theme.select(appearance) } label: {
            VStack(spacing: 6) {
                Image(systemName: appearance.systemImage)
                    .font(.title3)
                Text(appearance.displayName)
                    .font(.caption2).bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? JetsetterTheme.Colors.accent.opacity(0.15) : JetsetterTheme.Colors.surfaceElevated)
            .foregroundStyle(selected ? JetsetterTheme.Colors.accent : JetsetterTheme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? JetsetterTheme.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 0.5)
            )
        }
    }

    private func schemeChip(_ pref: ColorSchemePreference) -> some View {
        let selected = preferences.colorSchemePreference == pref
        return Button { preferences.colorSchemePreference = pref } label: {
            VStack(spacing: 6) {
                Image(systemName: pref.systemImage)
                    .font(.title3)
                Text(pref.displayName)
                    .font(.caption2).bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? JetsetterTheme.Colors.accent.opacity(0.15) : JetsetterTheme.Colors.surfaceElevated)
            .foregroundStyle(selected ? JetsetterTheme.Colors.accent : JetsetterTheme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? JetsetterTheme.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Travel Preferences

    private var travelSection: some View {
        @Bindable var preferences = preferences
        return settingsSection(title: "TRAVEL", icon: "globe") {
            VStack(spacing: 0) {
                // Home Airport
                HStack {
                    settingsLabel("Home Airport", icon: "airplane.departure")
                    Spacer()
                    Text(preferences.homeAirport.isEmpty ? "Not set" : preferences.homeAirport)
                        .font(.subheadline).bold()
                        .foregroundStyle(preferences.homeAirport.isEmpty
                                         ? JetsetterTheme.Colors.textSecondary
                                         : JetsetterTheme.Colors.accent)
                }
                settingsDivider()

                // Currency
                Picker(selection: $preferences.currency) {
                    ForEach(UserPreferences.supportedCurrencies, id: \.code) { c in
                        Text("\(c.code) — \(c.name)").tag(c.code)
                    }
                } label: {
                    settingsLabel("Currency", icon: "dollarsign.circle")
                }
                .tint(JetsetterTheme.Colors.accent)
                settingsDivider()

                // Distance unit
                Picker(selection: $preferences.distanceUnit) {
                    ForEach(DistanceUnit.allCases) { u in
                        Text(u.displayName).tag(u)
                    }
                } label: {
                    settingsLabel("Distance", icon: "ruler")
                }
                .tint(JetsetterTheme.Colors.accent)
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        @Bindable var preferences = preferences
        return settingsSection(title: "NOTIFICATIONS", icon: "bell.fill") {
            VStack(spacing: 0) {
                if !notifications.isAuthorized {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                        Text("Notifications are disabled. Enable them in iOS Settings.")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        Spacer()
                    }
                    .padding(.bottom, 12)
                }

                Toggle(isOn: $preferences.flightAlertsEnabled) {
                    settingsLabel("Flight Alerts", icon: "airplane.circle.fill",
                                  subtitle: "2h before departure")
                }
                .tint(JetsetterTheme.Colors.accent)
                .onChange(of: preferences.flightAlertsEnabled) { _, enabled in
                    Task {
                        if enabled { await TravelNotificationScheduler.shared.rescheduleAll() }
                        else       { await notifications.cancelFlightAlerts() }
                    }
                }
                settingsDivider()

                Toggle(isOn: $preferences.tripRemindersEnabled) {
                    settingsLabel("Trip Reminders", icon: "calendar.badge.clock",
                                  subtitle: "Morning of first trip day")
                }
                .tint(JetsetterTheme.Colors.accent)
                settingsDivider()

                Toggle(isOn: $preferences.expenseRemindersEnabled) {
                    settingsLabel("Weekly Expense Review", icon: "dollarsign.circle.fill",
                                  subtitle: "Every Sunday evening")
                }
                .tint(JetsetterTheme.Colors.accent)
                .onChange(of: preferences.expenseRemindersEnabled) { _, enabled in
                    Task {
                        if enabled { await notifications.scheduleWeeklyExpenseReminder() }
                        else       { notifications.cancelWeeklyExpenseReminder() }
                    }
                }
            }
        }
    }

    // MARK: - Travel Contacts (loved ones)

    private var travelContactsSection: some View {
        settingsSection(title: "TRAVEL CONTACTS", icon: "heart.fill") {
            VStack(spacing: 0) {
                NavigationLink {
                    LovedOnesSettingsView()
                } label: {
                    HStack {
                        settingsLabel("Loved Ones", icon: "person.2.fill",
                                      subtitle: "Text them on takeoff & landing")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
                Text("JetSetter Pro offers to text these contacts when your flight takes off and lands — or ask Siri to. You always tap Send; nothing is sent automatically.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        settingsSection(title: "DATA & PRIVACY", icon: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "iphone.and.arrow.forward.inward")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .frame(width: 20)
                    Text("Everything JetSetter Pro knows about your travel lives on this iPhone. There is no account and no cloud copy.")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                settingsDivider()
                Button(role: .destructive) {
                    showClearDataAlert = true
                } label: {
                    settingsLabel("Clear Local Data", icon: "trash.fill",
                                  iconColor: JetsetterTheme.Colors.danger)
                }
            }
        }
    }

    // MARK: - App Mode (demo vs beta, §7.2)

    #if DEMO_ENABLED
    private var demoSection: some View {
        settingsSection(title: "DEMO MODE", icon: "theatermasks.fill") {
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { demoIsOn },
                    set: { newValue in
                        guard !isSeedingDemo else { return }
                        demoIsOn = newValue
                        isSeedingDemo = true
                        Task {
                            if newValue { await DemoMode.enable() } else { DemoMode.disable() }
                            isSeedingDemo = false
                        }
                    }
                )) {
                    settingsLabel(
                        "Load sample trip",
                        icon: "airplane.departure",
                        subtitle: "Las Vegas to Atlanta on Delta 1423, with boarding pass, bags and expenses"
                    )
                }
                .tint(JetsetterTheme.Colors.accent)
                .disabled(isSeedingDemo)

                settingsDivider()

                Button {
                    showDemoResetAlert = true
                } label: {
                    settingsLabel("Rewind the demo", icon: "arrow.counterclockwise",
                                  iconColor: JetsetterTheme.Colors.accent,
                                  subtitle: "Puts departure back to 75 minutes out and clears the check-in")
                }
                .disabled(isSeedingDemo || !demoIsOn)

                settingsDivider()

                Text("Sample data is clearly marked and removed when you turn this off. It is not compiled into App Store builds. Weather is always live, never sampled.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .padding(.top, 10)
            }
        }
        .alert("Rewind the demo?", isPresented: $showDemoResetAlert) {
            Button("Rewind", role: .destructive) {
                isSeedingDemo = true
                Task {
                    await DemoMode.reseed()
                    demoIsOn = true
                    isSeedingDemo = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces the sample trip with a fresh copy. Your own trips, bags and expenses are not touched.")
        }
    }
    #endif

    // MARK: - Developer

    #if DEBUG
    private var developerSection: some View {
        settingsSection(title: "DEVELOPER", icon: "hammer.fill") {
            VStack(spacing: 0) {
                Button {
                    subscriptionManager.unlockForTesting()
                } label: {
                    HStack {
                        settingsLabel(
                            subscriptionManager.isProSubscriber ? "Pro Unlocked" : "Unlock Pro (Evaluation)",
                            icon: subscriptionManager.isProSubscriber ? "checkmark.seal.fill" : "crown.fill"
                        )
                        .foregroundStyle(subscriptionManager.isProSubscriber
                            ? JetsetterTheme.Colors.success
                            : JetsetterTheme.Colors.accent)
                        Spacer()
                        if subscriptionManager.isProSubscriber {
                            Text("Active")
                                .font(.caption.bold())
                                .foregroundStyle(JetsetterTheme.Colors.success)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(subscriptionManager.isProSubscriber)
            }
        }
    }
    #endif

    // MARK: - About

    private var aboutSection: some View {
        settingsSection(title: "ABOUT", icon: "info.circle.fill") {
            VStack(spacing: 0) {
                HStack {
                    settingsLabel("Version", icon: "tag.fill")
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .font(.subheadline)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                settingsDivider()
                settingsLink("Privacy Policy",   icon: "hand.raised.fill",   url: "https://jetsetterpro.app/privacy")
                settingsDivider()
                settingsLink("Terms of Service", icon: "doc.text.fill",      url: "https://jetsetterpro.app/terms")
                settingsDivider()
                // Native in-app review prompt (§7.7) instead of opening the App Store.
                Button {
                    InAppActions.requestReview()
                } label: {
                    HStack {
                        settingsLabel("Rate JetSetter Pro", icon: "star.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Component Helpers

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption).bold()
                Text(title)
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            // Content card
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .jetCard()
        }
    }

    @ViewBuilder
    private func settingsLabel(
        _ title: String,
        icon: String,
        iconColor: Color? = nil,
        subtitle: String? = nil,
        value: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor ?? JetsetterTheme.Colors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }

            if let val = value {
                Spacer()
                Text(val)
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
    }

    private func settingsDivider() -> some View {
        Divider()
            .background(JetsetterTheme.Colors.separator)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private func settingsLink(_ title: String, icon: String, url: String) -> some View {
        // Presents the page in an in-app web sheet rather than an external
        // browser (§7.7 in-app-only rule).
        Button {
            settingsWebURL = URL(string: url)
        } label: {
            HStack {
                settingsLabel(title, icon: icon)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func clearLocalData() {
        let defaults = UserDefaults.standard

        // Exact PII keys: trips, expenses, bags, wallet, the encrypted document
        // vault (passport/ID), loyalty, disruptions, digital ID, check-in state,
        // and any booked-ride marker.
        let exactKeys = [
            "jetsetter_trips",
            "jetsetter_expenses",
            "jetsetter_bags",
            "jetsetter_wallet_items",
            "jetsetter_vault_documents",
            "jetsetter_loyalty_accounts",
            "jetsetter_disruption_events_local",
            "jetsetter_id_state",
            "jetsetter_checked_in_flights",
            "uber_booked",
            "ride_opened_at",
            "uber_booked_details",
            "ride_on_landing_booked",
            "jetsetter_travel_signals",          // the app learning: behavioral signal log
            "jetsetter_learned_completed_trips", // the app learning: completed-trip dedup set
            "jetsetter_loved_ones"               // travel contacts (names + phone numbers)
        ]
        exactKeys.forEach { defaults.removeObject(forKey: $0) }

        // Reset the in-memory loved-ones list too (not just its persisted blob).
        LovedOnesStore.shared.removeAll()

        // Reset the in-memory learned profile too (not just its persisted signals).
        TravelProfileStore.shared.clearLearnedData()

        // Wallet, packing lists, disruption events and the signal mirror in the
        // local data store.
        Task { await LocalDataService.shared.clearAll() }

        // Prefix-keyed PII: per-trip offline kits & packing lists, per-currency
        // expense logs. Enumerate UserDefaults and remove every matching key.
        let prefixes = ["jetsetter_offline_kit_", "jetsetter_currency_expenses_", "packing_list_v1_"]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Bindable var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var name     = ""
    @State private var airport  = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Avatar preview
                ZStack {
                    Circle()
                        .fill(JetsetterTheme.Colors.goldGradient)
                        .frame(width: 80, height: 80)
                    Text(initials)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#0A0A10"))
                }
                .padding(.top, 24)

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                            .frame(width: 20)
                        TextField("Full name", text: $name)
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    }
                    .premiumInput()

                    HStack(spacing: 12) {
                        Image(systemName: "airplane.departure")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                            .frame(width: 20)
                        TextField("Home airport (IATA code)", text: $airport)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    }
                    .premiumInput()

                    // A real IATA code is exactly three A–Z letters (e.g. ATL, LHR).
                    // Show a hint the moment the field holds something that can't be
                    // a code, so a typo like "ATLL" or a city name is caught before Save.
                    if !airport.isEmpty && !isValidAirportCode {
                        Text("Enter a 3-letter airport code, like ATL or LHR.")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        preferences.displayName = name
                        // Only persist a valid 3-letter code; an empty field clears it
                        // ("Not set"). Reject anything that isn't a plausible IATA code.
                        preferences.homeAirport = isValidAirportCode
                            ? airport.trimmingCharacters(in: .whitespaces).uppercased()
                            : ""
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    // Block Save while the field holds an invalid (non-empty) code.
                    .disabled(!airport.isEmpty && !isValidAirportCode)
                }
            }
            .onAppear {
                name    = preferences.displayName
                airport = preferences.homeAirport
            }
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased().isEmpty ? "JS" :
               parts.map { String($0.prefix(1)) }.joined().uppercased()
    }

    /// True when the home-airport field is exactly three ASCII letters — the shape of
    /// every IATA code. Empty is handled separately (clears the field), so this only
    /// guards the "has content" case.
    private var isValidAirportCode: Bool {
        let code = airport.trimmingCharacters(in: .whitespaces)
        return code.count == 3 && code.allSatisfy { $0.isLetter && $0.isASCII }
    }
}

// MARK: - Bundle version helper

private extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(UserPreferences.shared)
        .environmentObject(NotificationManager.shared)
}
