// File: UI/Theme/JetsetterTheme.swift
// JetSetter Pro Design System

import SwiftUI
import UIKit

// MARK: - UIColor Hex Extension (used for adaptive dynamic colors)

extension UIColor {
    convenience init(hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                       .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8)  / 255,
            blue:  CGFloat( rgb & 0x0000FF)         / 255,
            alpha: 1
        )
    }
}

// MARK: - JetSetter Theme

enum JetsetterTheme {

    // MARK: - Color Palette

    enum Colors {

        // ── Backgrounds ──────────────────────────────────────────────────────

        /// Dark navy - the primary app canvas
        static let background = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#10131E")
                : UIColor(hex: "#EFF1F8")
        })

        /// Card / elevated surface
        static let surface = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#161929")
                : UIColor(hex: "#FFFFFF")
        })

        /// Deeper-elevated surface (inputs, inner cards)
        static let surfaceElevated = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#1D2235")
                : UIColor(hex: "#F4F5FB")
        })

        // ── Brand ─────────────────────────────────────────────────────────────

        /// Deep navy — primary brand identifier
        static let primary = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#1C3555")
                : UIColor(hex: "#0A2040")
        })

        /// Sky blue — the primary accent. Every button, tint, and highlight.
        static let accent = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#3B9EF0")   // vibrant sky blue
                : UIColor(hex: "#0055CC")   // royal blue for light-bg contrast
        })

        /// Softer blue — secondary informational accent
        static let blue = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#4E8FD4")
                : UIColor(hex: "#1A5FA8")
        })

        // ── Status ────────────────────────────────────────────────────────────

        /// Emerald green — on-time, success
        static let success = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#1DB97D")
                : UIColor(hex: "#0C7A4E")
        })

        /// Amber — delayed, warning
        static let warning = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#E8A020")
                : UIColor(hex: "#B07010")
        })

        /// Crimson — cancelled, error
        static let danger = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#E84040")
                : UIColor(hex: "#C42020")
        })

        // ── Text ──────────────────────────────────────────────────────────────

        static let textPrimary = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#ECEEF4")
                : UIColor(hex: "#0A0C18")
        })

        static let textSecondary = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#8B92A8")
                : UIColor(hex: "#52587A")
        })

        // ── Borders / Separators ───────────────────────────────────────────────

        static let separator = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#1E2136")
                : UIColor(hex: "#DDE0EE")
        })

        // ── Gradients ─────────────────────────────────────────────────────────

        /// Accent shimmer gradient — hero elements, labels, logo text
        static let goldGradient = LinearGradient(
            stops: [
                .init(color: Color(hex: "#1A72E8"), location: 0.0),
                .init(color: Color(hex: "#5BBAFF"), location: 0.45),
                .init(color: Color(hex: "#3A9AF0"), location: 0.75),
                .init(color: Color(hex: "#1A72E8"), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Deep dark gradient — onboarding backgrounds, hero sections
        static let heroGradient = LinearGradient(
            stops: [
                .init(color: Color(hex: "#06070D"), location: 0.0),
                .init(color: Color(hex: "#0D1425"), location: 0.5),
                .init(color: Color(hex: "#091530"), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Subtle card inner glow for depth (dark mode only)
        static let cardInnerGlow = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.04), location: 0.0),
                .init(color: Color.clear,               location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Accent card border shimmer (dark mode)
        static let goldBorderGradient = LinearGradient(
            stops: [
                .init(color: Color(hex: "#3B9EF0").opacity(0.30), location: 0.0),
                .init(color: Color.white.opacity(0.05),           location: 0.5),
                .init(color: Color(hex: "#3B9EF0").opacity(0.15), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography

    enum Typography {
        static let heroTitle: Font   = .system(size: 38, weight: .bold,     design: .rounded)
        static let displayTitle: Font = .system(size: 28, weight: .bold,    design: .rounded)
        static let pageTitle: Font   = .system(size: 22, weight: .bold,     design: .rounded)
        static let cardTitle: Font   = .system(size: 17, weight: .semibold, design: .default)
        static let bodyMedium: Font  = .system(size: 15, weight: .medium,   design: .default)
        static let metric: Font      = .system(size: 34, weight: .bold,     design: .rounded)
        static let label: Font       = .system(size: 12, weight: .semibold, design: .rounded)
        static let caption: Font     = .system(size: 11, weight: .medium,   design: .default)
    }

    // MARK: - Card Constants

    enum Card {
        static let cornerRadius: CGFloat = 18
        static let padding: CGFloat      = 16
    }

    // MARK: - Spacing

    enum Spacing {
        static let xsmall: CGFloat = 4
        static let small: CGFloat  = 8
        static let medium: CGFloat = 16
        static let large: CGFloat  = 24
        static let xlarge: CGFloat = 32
    }
}

// MARK: - Glass Card Modifier

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                        .fill(scheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.white))

                    if scheme == .dark {
                        RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                            .fill(JetsetterTheme.Colors.cardInnerGlow)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                        .strokeBorder(
                            scheme == .dark
                                ? AnyShapeStyle(JetsetterTheme.Colors.goldBorderGradient)
                                : AnyShapeStyle(Color.black.opacity(0.06)),
                            lineWidth: 0.6
                        )
                }
                .shadow(
                    color: scheme == .dark ? .black.opacity(0.55) : .black.opacity(0.06),
                    radius: scheme == .dark ? 24 : 10,
                    x: 0,
                    y: scheme == .dark ? 12 : 4
                )
            }
    }
}

extension View {
    func jetCard() -> some View { modifier(CardStyle()) }
}

// MARK: - Accent Text Gradient Modifier

struct GoldTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(JetsetterTheme.Colors.goldGradient)
    }
}

extension View {
    func goldText() -> some View { modifier(GoldTextModifier()) }
}

// MARK: - Accent Capsule Tag

struct GoldTag: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).font(JetsetterTheme.Typography.label)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(JetsetterTheme.Colors.accent.opacity(0.15))
        .foregroundStyle(JetsetterTheme.Colors.accent)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(JetsetterTheme.Colors.accent.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Premium Input Field Style

struct PremiumInputStyle: ViewModifier {
    @Environment(\.colorScheme) var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(scheme == .dark
                          ? AnyShapeStyle(Color(UIColor(hex: "#141726")))
                          : AnyShapeStyle(Color(UIColor(hex: "#F4F5FB"))))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                scheme == .dark
                                    ? Color(hex: "#3B9EF0").opacity(0.18)
                                    : Color.black.opacity(0.06),
                                lineWidth: 0.5
                            )
                    }
            }
    }
}

extension View {
    func premiumInput() -> some View { modifier(PremiumInputStyle()) }
}

// MARK: - Color Hex Initializer (SwiftUI)

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                       .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8)  / 255.0,
            blue:  Double( rgb & 0x0000FF)         / 255.0
        )
    }
}

// MARK: - Flight Status Color

extension String {
    var flightStatusColor: Color {
        switch self.lowercased() {
        case "on time", "scheduled", "active": return JetsetterTheme.Colors.success
        case "delayed":                         return JetsetterTheme.Colors.warning
        case "cancelled", "diverted":           return JetsetterTheme.Colors.danger
        default:                                return JetsetterTheme.Colors.textSecondary
        }
    }
}
