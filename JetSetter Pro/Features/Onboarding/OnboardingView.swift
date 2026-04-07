// File: Features/Onboarding/OnboardingView.swift

import SwiftUI

// MARK: - Onboarding Page Model

struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let accentLine: String?     // short highlighted phrase shown above title
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
            iconColor: Color(hex: "#C9A84C"),
            title: "Welcome to\nJetSetter Pro",
            subtitle: "Your world-class travel companion. Built for executives who expect everything to work perfectly.",
            accentLine: "PRIVATE. PRECISE. POWERFUL."
        ),
        OnboardingPage(
            icon: "briefcase.fill",
            iconColor: Color(hex: "#C9A84C"),
            title: "Everything\nIn One Place",
            subtitle: "Flights, hotels, ground transport, rental cars, itineraries, and expenses — seamlessly unified.",
            accentLine: "8 INTEGRATED FEATURES"
        ),
        OnboardingPage(
            icon: "sparkles",
            iconColor: Color(hex: "#C9A84C"),
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

            // Subtle star field
            StarFieldView()
                .ignoresSafeArea()

            // ── Content ─────────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Logo mark
                logoHeader
                    .padding(.top, 60)

                // Page carousel
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageContent(page: page)
                            .tag(index)
                    }
                    // Final page: Setup
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
                                      ? Color(hex: "#C9A84C")
                                      : Color.white.opacity(0.25))
                                .frame(width: i == currentPage ? 24 : 6, height: 6)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                        }
                    }

                    // Primary button
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
                .overlay(Capsule().strokeBorder(Color(hex: "#C9A84C").opacity(0.3), lineWidth: 0.5))
        }
        .scaleEffect(logoScale)
        .opacity(logoOpacity)
    }

    // MARK: - Setup Page (last page)

    private var setupPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#C9A84C").opacity(0.12))
                            .frame(width: 88, height: 88)
                            .overlay(Circle().strokeBorder(Color(hex: "#C9A84C").opacity(0.3), lineWidth: 0.8))
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

                // Form fields
                VStack(spacing: 16) {
                    setupField(icon: "person.fill",
                               placeholder: "Your name",
                               text: $displayName)

                    setupField(icon: "airplane.departure",
                               placeholder: "Home airport (e.g. JFK, ORD)",
                               text: $homeAirport)

                    // Currency picker
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

                // Appearance
                VStack(alignment: .leading, spacing: 12) {
                    Text("APPEARANCE")
                        .font(JetsetterTheme.Typography.label)
                        .foregroundStyle(Color(hex: "#C9A84C"))
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
            .background(selected ? Color(hex: "#C9A84C").opacity(0.2) : Color.white.opacity(0.06))
            .foregroundStyle(selected ? Color(hex: "#C9A84C") : Color.white.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color(hex: "#C9A84C").opacity(0.5) : Color.white.opacity(0.1),
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
            .background(goldButtonBackground)
            .foregroundStyle(Color(hex: "#0A0A10"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: "#C9A84C").opacity(0.4), radius: 16, x: 0, y: 8)
        }
    }

    private var goldButtonBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "#E8C877"), location: 0.0),
                .init(color: Color(hex: "#C9A84C"), location: 0.5),
                .init(color: Color(hex: "#B8962E"), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Completion

    private func completeOnboarding() {
        // Save profile
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

            // Icon ring
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(page.iconColor.opacity(0.06))
                    .frame(width: 160, height: 160)
                Circle()
                    .fill(page.iconColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .overlay(Circle().strokeBorder(page.iconColor.opacity(0.25), lineWidth: 0.8))
                // Icon
                Image(systemName: page.icon)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(JetsetterTheme.Colors.goldGradient)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)

            // Accent line
            if let accent = page.accentLine {
                Text(accent)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(JetsetterTheme.Colors.goldGradient)
            }

            // Title
            Text(page.title)
                .font(JetsetterTheme.Typography.heroTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            // Subtitle
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

// MARK: - Star Field (subtle ambient background)

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

// MARK: - Currency Picker (sheet)
// TODO: Wire up `showCurrencyPicker` sheet presentation

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(UserPreferences.shared)
}
