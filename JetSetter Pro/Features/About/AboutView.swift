// File: Features/About/AboutView.swift
//
// About JetSetter Pro — brand hero, a swipeable feature tour built from the
// product showcase screens, and a note from the founder. All imagery lives in
// Assets.xcassets (FounderHeadshot + Showcase* imagesets).

import SwiftUI

struct AboutView: View {

    /// A single slide in the feature tour.
    private struct Showcase: Identifiable {
        let id = UUID()
        let asset: String
        let title: String
        let caption: String
    }

    private let tour: [Showcase] = [
        .init(asset: "ShowcaseHome",
              title: "Home",
              caption: "Your whole travel day at a glance — live flight, gate, seat and the next smart move."),
        .init(asset: "ShowcaseDisruption",
              title: "Disruption AI",
              caption: "Delays and cancellations handled before you ask — rebookings found, hotels notified."),
        .init(asset: "ShowcaseIRIS",
              title: "IRIS",
              caption: "Your proactive AI travel agent — routing, timing, loyalty and rides in real time."),
        .init(asset: "ShowcaseWallet",
              title: "Travel Wallet",
              caption: "Boarding passes, hotels and coverage in one elegant, always-ready place."),
        .init(asset: "ShowcaseExpenses",
              title: "Expenses",
              caption: "Multi-currency spend tracking and one-tap expense reports on the road."),
        .init(asset: "ShowcaseInflight",
              title: "In-Flight",
              caption: "Live altitude, GPS position and flight-phase detection — even offline.")
    ]

    @State private var tourIndex = 0

    /// Image and page heights scale with the user's Dynamic Type setting so
    /// captions and the page-index dots are never clipped at accessibility
    /// sizes or on smaller devices.
    @ScaledMetric(relativeTo: .body) private var tourImageHeight: CGFloat = 420
    @ScaledMetric(relativeTo: .body) private var tourPageHeight: CGFloat = 540

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                heroSection
                featureTour
                founderCard
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(JetsetterTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [JetsetterTheme.Colors.accent.opacity(0.22),
                                     JetsetterTheme.Colors.accent.opacity(0.04)],
                            center: .center, startRadius: 0, endRadius: 48
                        )
                    )
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(JetsetterTheme.Colors.accent.opacity(0.35), lineWidth: 1.5))

                Image(systemName: "airplane")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .rotationEffect(.degrees(-45))
                    .accessibilityHidden(true)
            }

            Text("JetSetter Pro")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .goldText()

            Text("YOUR EXECUTIVE TRAVEL COMPANION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(3)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)

            if let versionString {
                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary.opacity(0.7))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Feature Tour

    private var featureTour: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "TAKE THE TOUR", icon: "sparkles")

            TabView(selection: $tourIndex) {
                ForEach(Array(tour.enumerated()), id: \.offset) { index, slide in
                    VStack(spacing: 16) {
                        Image(slide.asset)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: tourImageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .strokeBorder(JetsetterTheme.Colors.goldBorderGradient, lineWidth: 0.8)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
                            .accessibilityLabel(slide.title)

                        VStack(spacing: 6) {
                            Text(slide.title)
                                .font(JetsetterTheme.Typography.cardTitle)
                                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                            Text(slide.caption)
                                .font(JetsetterTheme.Typography.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 36)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: tourPageHeight)
        }
    }

    // MARK: - Founder

    private var founderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "FROM THE FOUNDER", icon: "quote.bubble.fill")

            VStack(spacing: 16) {
                Image("FounderHeadshot")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(JetsetterTheme.Colors.goldBorderGradient, lineWidth: 1))
                    .shadow(color: JetsetterTheme.Colors.accent.opacity(0.25), radius: 12)

                Text("“We built JetSetter Pro for people who live on the road — so the app handles the delays, the rebookings and the logistics, and you just travel like an executive.”")
                    .font(.system(size: 15, weight: .medium))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 2) {
                    Text("Founder & CEO")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                    Text("Trainovate Technologies LLC")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .jetCard()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Powered by Claude")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.8))

            Text("© 2026 Trainovate Technologies LLC")
                .font(.caption2)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption).bold()
            Text(title)
                .font(JetsetterTheme.Typography.label)
                .tracking(1.5)
        }
        .foregroundStyle(JetsetterTheme.Colors.accent)
        .padding(.leading, 4)
    }

    /// Real version/build from Info.plist, or `nil` when the keys can't be
    /// read — in which case the version line is omitted rather than showing a
    /// fabricated "1.0 (1)" that would mislead support/QA.
    private var versionString: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String else {
            return nil
        }
        return "Version \(version) (\(build))"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AboutView()
    }
}
