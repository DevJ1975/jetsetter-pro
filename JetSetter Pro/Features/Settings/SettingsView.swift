// File: Features/Settings/SettingsView.swift

import SwiftUI

struct SettingsView: View {

    @Environment(UserPreferences.self) private var preferences
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @EnvironmentObject private var theme: JetThemeStore

    // Supabase auth state
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
    @State private var showDeleteAccountError = false

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
                    travelContactsSection
                    accountSection
                    dataSection
                    presentationSection
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
            .alert("Account deletion failed", isPresented: $showDeleteAccountError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Account deletion failed, please try again. Your account and data have not been changed.")
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

                // IRIS Learning — opt-in. IRIS learns the traveler's seat/airline/spend
                // patterns from their own activity, fully on-device. Master switch plus
                // per-source controls; "What IRIS Has Learned" shows & clears the profile.
                Toggle(isOn: $preferences.learningEnabled) {
                    settingsLabel("Let IRIS Learn From My Activity", icon: "brain.head.profile")
                }
                .tint(JetsetterTheme.Colors.accent)
                .onChange(of: preferences.learningEnabled) { _, _ in
                    TravelProfileStore.shared.recompute()
                }

                // Per-source controls stay visible even when the master is off, so a
                // privacy-conscious user can always audit exactly what IRIS is allowed
                // to learn. When the master is off they're greyed out (disabled), and
                // "What IRIS Has Learned" is hidden since there's nothing to inspect.
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
                        IRISLearnedProfileView()
                    } label: {
                        settingsLabel("What IRIS Has Learned", icon: "sparkles.rectangle.stack")
                    }
                    .padding(.top, 4)
                }

                Text("IRIS learns only on your device, from your own activity — never shared. Turn off any source, or wipe everything with Clear Local Data.")
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
                Text("IRIS offers to text these contacts when your flight takes off and lands. You always tap Send — nothing is sent automatically.")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
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
                                    Text(isSyncing ? "Backing up…" : (syncStatus ?? "Back Up to Cloud"))
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

    // MARK: - App Mode (demo vs beta, §7.2)

    private var presentationSection: some View {
        settingsSection(title: "APP MODE", icon: "sparkles.tv.fill") {
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
                    settingsLabel(
                        demoMode ? "Demo mode" : "Beta mode",
                        icon: demoMode ? "play.rectangle.fill" : "hammer.circle.fill",
                        subtitle: demoMode
                            ? "Seeded persona + sample data (Jordan Ellis · DL 1423). Turn off for beta."
                            : "Live services and your real data. Turn on for a scripted demo."
                    )
                }
                .tint(JetsetterTheme.Colors.accent)

                // Reset only applies while seeding demo data.
                if demoMode {
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
    }

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
                // Hidden 5-tap demo-reset gesture. Ships DEBUG-only so a curious
                // App Store user can't tap the version label and wipe/re-seed
                // their real data with the demo persona. Matches the #if DEBUG
                // gating on developerSection / presentation reset affordances.
                #if DEBUG
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
                #endif
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
            // Server-side deletion failed. Do NOT wipe local data or sign out —
            // the account still exists in the cloud, so treating this as success
            // would strand the user's data server-side. Keep them signed in and
            // surface a dedicated error so they can retry.
            isDeletingAccount = false
            showDeleteAccountError = true
            return
        }
        // Only reached once the server confirms deletion.
        clearLocalData()
        signedInUser = nil
        preferences.email = ""
        isDeletingAccount = false
    }

    private func syncToCloud() async {
        isSyncing = true
        syncStatus = nil
        do {
            // Load local data and sync. Decode with `try` (not `try?`) so a
            // corrupt/schema-drifted blob throws into the catch below rather than
            // silently yielding nil and masquerading as a successful sync. A
            // genuinely absent key (no data yet) is still treated as "nothing to
            // push" via the if-let on the data itself.
            var syncedTrips = 0
            var syncedExpenses = 0
            if let tripData = UserDefaults.standard.data(forKey: "jetsetter_trips") {
                let trips = try JSONDecoder().decode([Trip].self, from: tripData)
                try await SupabaseService.shared.syncTrips(trips)
                syncedTrips = trips.count
            }
            if let expenseData = UserDefaults.standard.data(forKey: "jetsetter_expenses") {
                let expenses = try JSONDecoder().decode([Expense].self, from: expenseData)
                try await SupabaseService.shared.syncExpenses(expenses)
                syncedExpenses = expenses.count
            }
            syncStatus = "Backed up \(syncedTrips) trips, \(syncedExpenses) expenses ✓"
        } catch {
            syncStatus = "Backup failed"
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
            "uber_booked",
            "jetsetter_travel_signals",          // IRIS learning: behavioral signal log
            "jetsetter_learned_completed_trips", // IRIS learning: completed-trip dedup set
            "jetsetter_loved_ones"               // travel contacts (names + phone numbers)
        ]
        exactKeys.forEach { defaults.removeObject(forKey: $0) }

        // Reset the in-memory loved-ones list too (not just its persisted blob).
        LovedOnesStore.shared.removeAll()

        // Reset the in-memory learned profile too (not just its persisted signals).
        TravelProfileStore.shared.clearLearnedData()

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
