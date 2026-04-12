// File: Features/Onboarding/OnboardingView.swift

import SwiftUI

// MARK: - Onboarding Page Model

struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let accentLine: String?
}

// MARK: - Onboarding View

struct OnboardingView: View {

    @EnvironmentObject private var preferences: UserPreferences
    @State private var currentPage  = 0
    @State private var displayName  = ""
    @State private var homeAirport  = ""
    @State private var currency     = "USD"
    @State private var showCurrencyPicker = false
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: CGFloat = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "airplane",
            iconColor: JetsetterTheme.Colors.accent,
            title: "Welcome to\nJetSetter Pro",
            subtitle: "Your world-class travel companion. Built for executives who expect everything to work perfectly.",
            accentLine: "PRIVATE. PRECISE. POWERFUL."
        ),
        OnboardingPage(
            icon: "briefcase.fill",
            iconColor: JetsetterTheme.Colors.accent,
            title: "Everything\nIn One Place",
            subtitle: "Flights, hotels, ground transport, rental cars, itineraries, and expenses — seamlessly unified.",
            accentLine: "8 INTEGRATED FEATURES"
        ),
        OnboardingPage(
            icon: "sparkles",
            iconColor: JetsetterTheme.Colors.accent,
            title: "Your AI Travel\nConcierge",
            subtitle: "Powered by Claude — ask anything. Get instant, expert travel advice personalized to your journey.",
            accentLine: "POWERED BY CLAUDE AI"
        )
    ]

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────────────
            JetsetterTheme.Colors.heroGradient
                .ignoresSafeArea()

            StarFieldView()
                .ignoresSafeArea()

            // ── Content ─────────────────────────────────────────────────────
            VStack(spacing: 0) {
                logoHeader
                    .padding(.top, 60)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageContent(page: page)
                            .tag(index)
                    }
                    setupPage
                        .tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // ── Bottom Controls ──────────────────────────────────────────
                VStack(spacing: 24) {
                    // Dot indicator
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count + 1, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage
                                      ? JetsetterTheme.Colors.accent
                                      : Color.white.opacity(0.25))
                                .frame(width: i == currentPage ? 24 : 6, height: 6)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                        }
                    }

                    primaryButton
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                logoScale   = 1.0
                logoOpacity = 1.0
            }
        }
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                List(UserPreferences.supportedCurrencies, id: \.code) { item in
                    Button {
                        currency = item.code
                        showCurrencyPicker = false
                    } label: {
                        HStack {
                            Text(item.code)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(width: 52, alignment: .leading)
                            Text(item.name)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if currency == item.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(JetsetterTheme.Colors.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityLabel("\(item.name), \(item.code)\(currency == item.code ? ", selected" : "")")
                }
                .navigationTitle("Select Currency")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showCurrencyPicker = false }
                    }
                }
            }
        }
    }

    // MARK: - Logo Header

    private var logoHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(JetsetterTheme.Colors.goldGradient)

            Text("JETSETTER PRO")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(JetsetterTheme.Colors.goldGradient)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(JetsetterTheme.Colors.accent.opacity(0.3), lineWidth: 0.5))
        }
        .scaleEffect(logoScale)
        .opacity(logoOpacity)
    }

    // MARK: - Setup Page (last page)

    private var setupPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(JetsetterTheme.Colors.accent.opacity(0.12))
                            .frame(width: 88, height: 88)
                            .overlay(Circle().strokeBorder(JetsetterTheme.Colors.accent.opacity(0.3), lineWidth: 0.8))
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(JetsetterTheme.Colors.goldGradient)
                    }
                    Text("Let's Personalize\nYour Experience")
                        .font(JetsetterTheme.Typography.displayTitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("Tell us a bit about yourself to tailor JetSetter Pro to your travel style.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    setupField(icon: "person.fill",
                               placeholder: "Your name",
                               text: $displayName)

                    setupField(icon: "airplane.departure",
                               placeholder: "Home airport (e.g. JFK, ORD)",
                               text: $homeAirport)

                    Button { showCurrencyPicker = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                                .frame(width: 20)
                            Text(currencyDisplayText)
                                .foregroundStyle(displayName.isEmpty ? Color.white.opacity(0.4) : .white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        .premiumInput()
                    }
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 12) {
                    Text("APPEARANCE")
                        .font(JetsetterTheme.Typography.label)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .tracking(1.5)

                    HStack(spacing: 8) {
                        ForEach(ColorSchemePreference.allCases) { pref in
                            appearanceChip(pref)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }

    private var currencyDisplayText: String {
        let match = UserPreferences.supportedCurrencies.first { $0.code == currency }
        return match.map { "\($0.code) — \($0.name)" } ?? "Currency"
    }

    private func setupField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .foregroundStyle(.white)
                .tint(JetsetterTheme.Colors.accent)
                .autocorrectionDisabled()
        }
        .premiumInput()
    }

    private func appearanceChip(_ pref: ColorSchemePreference) -> some View {
        let selected = preferences.colorSchemePreference == pref
        return Button {
            preferences.colorSchemePreference = pref
        } label: {
            HStack(spacing: 6) {
                Image(systemName: pref.systemImage)
                    .font(.caption)
                Text(pref.displayName)
                    .font(.caption).bold()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(selected ? JetsetterTheme.Colors.accent.opacity(0.2) : Color.white.opacity(0.06))
            .foregroundStyle(selected ? JetsetterTheme.Colors.accent : Color.white.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? JetsetterTheme.Colors.accent.opacity(0.5) : Color.white.opacity(0.1),
                                  lineWidth: 0.5)
            )
        }
    }

    // MARK: - Primary Button

    private var primaryButton: some View {
        Button {
            if currentPage < pages.count {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentPage += 1
                }
            } else {
                completeOnboarding()
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentPage < pages.count ? "Continue" : "Get Started")
                    .font(.system(size: 17, weight: .bold))
                Image(systemName: currentPage < pages.count ? "arrow.right" : "checkmark")
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(buttonBackground)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: JetsetterTheme.Colors.accent.opacity(0.45), radius: 16, x: 0, y: 8)
        }
    }

    private var buttonBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "#5AB0FF"), location: 0.0),
                .init(color: Color(hex: "#2E82F0"), location: 0.5),
                .init(color: Color(hex: "#1A68DC"), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Completion

    private func completeOnboarding() {
        if !displayName.isEmpty  { preferences.displayName = displayName }
        if !homeAirport.isEmpty  { preferences.homeAirport = homeAirport.uppercased() }
        preferences.currency = currency

        withAnimation(.easeInOut(duration: 0.4)) {
            preferences.hasCompletedOnboarding = true
        }
    }
}

// MARK: - Onboarding Page Content

struct OnboardingPageContent: View {
    let page: OnboardingPage
    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.06))
                    .frame(width: 160, height: 160)
                Circle()
                    .fill(page.iconColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .overlay(Circle().strokeBorder(page.iconColor.opacity(0.25), lineWidth: 0.8))
                Image(systemName: page.icon)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(JetsetterTheme.Colors.goldGradient)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)

            if let accent = page.accentLine {
                Text(accent)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(JetsetterTheme.Colors.goldGradient)
            }

            Text(page.title)
                .font(JetsetterTheme.Typography.heroTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text(page.subtitle)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.58))
                .lineSpacing(4)
                .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) {
                iconScale   = 1.0
                iconOpacity = 1.0
            }
        }
        .onDisappear {
            iconScale   = 0.7
            iconOpacity = 0
        }
    }
}

// MARK: - Star Field

struct StarFieldView: View {
    private struct Star: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: CGFloat
    }

    private let stars: [Star] = (0..<60).map { _ in
        Star(
            x:       CGFloat.random(in: 0...1),
            y:       CGFloat.random(in: 0...1),
            size:    CGFloat.random(in: 1...2.5),
            opacity: CGFloat.random(in: 0.1...0.5)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(stars) { star in
                Circle()
                    .fill(Color.white.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .position(x: star.x * geo.size.width, y: star.y * geo.size.height)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(UserPreferences.shared)
}
