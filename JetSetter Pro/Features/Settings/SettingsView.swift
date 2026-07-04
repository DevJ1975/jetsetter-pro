// File: Features/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var preferences: UserPreferences
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // Firebase auth state
    @State private var signedInUser: SupabaseUser? = nil   // loaded async from actor
    @AppStorage("demoMode") private var demoMode = false   // presentation demo switch (§7.2)
    @State private var settingsWebURL: URL?   // in-app web sheet (Privacy/Terms, §7.7)
    @State private var authEmail    = ""
    @State private var authPassword = ""
    @State private var authError: String? = nil
    @State private var isAuthLoading = false
    @State private var showSignUp    = false
    @State private var syncStatus: String? = nil
    @State private var isSyncing     = false

    // Edit profile
    @State private var editName     = ""
    @State private var editAirport  = ""
    @State private var isEditingProfile = false

    // Hidden demo-reset gesture: 5 taps on the version label.
    @State private var versionTapCount = 0
    @State private var showDemoResetConfirm = false

    // Alert
    @State private var showClearDataAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false

    // Subscription
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileCard
                    subscriptionSection
                    appearanceSection
                    travelSection
                    notificationsSection
                    accountSection
                    dataSection
                    #if DEBUG
                    presentationSection
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
                    .environmentObject(subscriptionManager)
            }
            .task {
                signedInUser = await SupabaseService.shared.currentUser
            }
            .alert("Clear Local Data?", isPresented: $showClearDataAlert) {
                Button("Clear All", role: .destructive) { clearLocalData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all locally saved travel data (trips, expenses, bags, documents, and more). This cannot be undone.")
            }
            .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
                Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your JetSetter Pro account and all synced data, and removes everything stored on this device. This cannot be undone.")
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
                            Text("Unlock all features · Pay with Apple Pay")
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
        settingsSection(title: "APPEARANCE", icon: "paintbrush.fill") {
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
            }
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
        settingsSection(title: "TRAVEL", icon: "globe") {
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
        settingsSection(title: "NOTIFICATIONS", icon: "bell.fill") {
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
                    if !enabled { Task { notifications.cancelAllNotifications() } }
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

    // MARK: - Account (Supabase)

    private var accountSection: some View {
        settingsSection(title: "ACCOUNT", icon: "person.crop.circle.fill") {
            VStack(spacing: 0) {
                // Auth state loaded asynchronously from the actor (see .task above)
                Group {
                    if let user = signedInUser {
                        // Signed in
                        VStack(spacing: 12) {
                            HStack {
                                settingsLabel("Signed in as", icon: "checkmark.seal.fill")
                                Spacer()
                                Text(user.email ?? "—")
                                    .font(.caption)
                                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            }

                            settingsDivider()

                            // Sync button
                            Button {
                                Task { await syncToCloud() }
                            } label: {
                                HStack {
                                    if isSyncing {
                                        ProgressView().scaleEffect(0.8).tint(JetsetterTheme.Colors.accent)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(isSyncing ? "Syncing…" : (syncStatus ?? "Sync to Cloud"))
                                        .font(.subheadline).bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(JetsetterTheme.Colors.accent.opacity(0.12))
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .disabled(isSyncing)

                            settingsDivider()

                            Button(role: .destructive) {
                                Task { await signOut() }
                            } label: {
                                settingsLabel("Sign Out", icon: "rectangle.portrait.and.arrow.right",
                                              iconColor: JetsetterTheme.Colors.danger)
                            }

                            settingsDivider()

                            Button(role: .destructive) {
                                showDeleteAccountAlert = true
                            } label: {
                                HStack(spacing: 8) {
                                    if isDeletingAccount {
                                        ProgressView().scaleEffect(0.8).tint(JetsetterTheme.Colors.danger)
                                    }
                                    settingsLabel("Delete Account", icon: "trash.fill",
                                                  iconColor: JetsetterTheme.Colors.danger)
                                }
                            }
                            .disabled(isDeletingAccount)
                        }
                    } else {
                        // Signed out — show auth form
                        VStack(spacing: 12) {
                            Group {
                                HStack(spacing: 12) {
                                    Image(systemName: "envelope.fill")
                                        .foregroundStyle(JetsetterTheme.Colors.accent)
                                        .frame(width: 20)
                                    TextField("Email address", text: $authEmail)
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                                }
                                .premiumInput()

                                HStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(JetsetterTheme.Colors.accent)
                                        .frame(width: 20)
                                    SecureField("Password", text: $authPassword)
                                        .textContentType(showSignUp ? .newPassword : .password)
                                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                                }
                                .premiumInput()
                            }

                            if let err = authError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(JetsetterTheme.Colors.danger)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    Task { showSignUp ? await signUp() : await signIn() }
                                } label: {
                                    HStack {
                                        if isAuthLoading { ProgressView().scaleEffect(0.8) }
                                        Text(showSignUp ? "Create Account" : "Sign In")
                                            .font(.subheadline).bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(JetsetterTheme.Colors.accent)
                                    .foregroundStyle(Color(hex: "#0A0A10"))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .disabled(isAuthLoading)

                                Button {
                                    showSignUp.toggle()
                                    authError = nil
                                } label: {
                                    Text(showSignUp ? "Sign In" : "Sign Up")
                                        .font(.subheadline)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(JetsetterTheme.Colors.surfaceElevated)
                                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }

                            Text("Your data syncs across all your devices when signed in.")
                                .font(.caption)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        settingsSection(title: "DATA & PRIVACY", icon: "lock.shield.fill") {
            VStack(spacing: 0) {
                Button(role: .destructive) {
                    showClearDataAlert = true
                } label: {
                    settingsLabel("Clear Local Data", icon: "trash.fill",
                                  iconColor: JetsetterTheme.Colors.danger)
                }
            }
        }
    }

    // MARK: - Presentation (demo mode, §7.2)

    #if DEBUG
    private var presentationSection: some View {
        settingsSection(title: "PRESENTATION", icon: "sparkles.tv.fill") {
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { demoMode },
                    set: { newValue in
                        Task {
                            if newValue { await DemoMode.enable() }
                            else        { DemoMode.disable() }
                        }
                    }
                )) {
                    settingsLabel("Demo mode", icon: "play.rectangle.fill",
                                  subtitle: "Seed the investor persona (Jordan Ellis · DL 1423)")
                }
                .tint(JetsetterTheme.Colors.accent)

                settingsDivider()

                Button {
                    Task { await DemoMode.resetData() }
                } label: {
                    HStack {
                        settingsLabel("Reset demo data", icon: "arrow.counterclockwise")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Developer

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
                .contentShape(Rectangle())
                .onTapGesture {
                    versionTapCount += 1
                    if versionTapCount >= 5 {
                        versionTapCount = 0
                        showDemoResetConfirm = true
                    }
                }
                .confirmationDialog(
                    "Reset demo data?",
                    isPresented: $showDemoResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset all demo data", role: .destructive) {
                        Task { await DemoMode.resetData() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Wipes all seeded trips, expenses, wallet items, loyalty accounts, and IRIS memory. Relaunch to re-seed.")
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

    private func signIn() async {
        guard !authEmail.isEmpty, !authPassword.isEmpty else { return }
        isAuthLoading = true
        authError = nil
        do {
            _ = try await SupabaseService.shared.signIn(email: authEmail, password: authPassword)
            preferences.email = authEmail
            signedInUser = await SupabaseService.shared.currentUser
        } catch {
            authError = error.localizedDescription
        }
        isAuthLoading = false
    }

    private func signUp() async {
        guard !authEmail.isEmpty, !authPassword.isEmpty else { return }
        isAuthLoading = true
        authError = nil
        do {
            _ = try await SupabaseService.shared.signUp(email: authEmail, password: authPassword)
            preferences.email = authEmail
            signedInUser = await SupabaseService.shared.currentUser
        } catch {
            authError = error.localizedDescription
        }
        isAuthLoading = false
    }

    private func signOut() async {
        await SupabaseService.shared.signOut()
        signedInUser = nil
        preferences.email = ""
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        do {
            try await SupabaseService.shared.deleteAccount()
        } catch {
            // Surface the error, but still wipe locally + sign out so the user's
            // data never lingers on-device after a delete request.
            authError = error.localizedDescription
        }
        clearLocalData()
        signedInUser = nil
        preferences.email = ""
        isDeletingAccount = false
    }

    private func syncToCloud() async {
        isSyncing = true
        syncStatus = nil
        do {
            // Load local data and sync
            if let tripData = UserDefaults.standard.data(forKey: "jetsetter_trips"),
               let trips = try? JSONDecoder().decode([Trip].self, from: tripData) {
                try await SupabaseService.shared.syncTrips(trips)
            }
            if let expenseData = UserDefaults.standard.data(forKey: "jetsetter_expenses"),
               let expenses = try? JSONDecoder().decode([Expense].self, from: expenseData) {
                try await SupabaseService.shared.syncExpenses(expenses)
            }
            syncStatus = "Synced ✓"
        } catch {
            syncStatus = "Sync failed"
        }
        isSyncing = false
    }

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
            "uber_booked"
        ]
        exactKeys.forEach { defaults.removeObject(forKey: $0) }

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
    @ObservedObject var preferences: UserPreferences
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
                        preferences.homeAirport = airport.uppercased()
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(JetsetterTheme.Colors.accent)
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
        .environmentObject(UserPreferences.shared)
        .environmentObject(NotificationManager.shared)
}
