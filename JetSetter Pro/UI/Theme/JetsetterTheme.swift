// File: UI/Theme/JetsetterTheme.swift
// JetSetter Pro Executive Design System
// Dark-first, gold-accented, glass-morphism UI language.

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

// MARK: - JetSetter Executive Theme

enum JetsetterTheme {

    // MARK: - Color Palette
    // All colors are adaptive: designed to look premium in dark mode,
    // clean and professional in light mode.

    enum Colors {

        // ── Backgrounds ──────────────────────────────────────────────────────

        /// Dark navy - the primary app canvas (slightly lightened for readability)
        static let background = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#10131E")   // deep navy with blue depth
                : UIColor(hex: "#EFF1F8")   // cool off-white
        })

        /// Card / elevated surface
        static let surface = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#161929")   // dark navy surface
                : UIColor(hex: "#FFFFFF")
        })

        /// Deeper-elevated surface (inputs, inner cards)
        static let surfaceElevated = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#1D2235")   // inset dark navy
                : UIColor(hex: "#F4F5FB")
        })

        // ── Brand ─────────────────────────────────────────────────────────────

        /// Deep navy — primary brand identifier
        static let primary = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#1C3555")
                : UIColor(hex: "#0A2040")
        })

        /// Rich gold — the executive accent. Every button, tint, and highlight.
        static let accent = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#C9A84C")   // warm champagne gold
                : UIColor(hex: "#9B7A2A")   // darker for light-bg contrast
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

        /// Amber gold — delayed, warning
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

        /// Platinum white (dark) / near-black (light)
        static let textPrimary = Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: "#ECEEF4")
                : UIColor(hex: "#0A0C18")
        })

        /// Muted steel — secondary labels
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

        /// Signature gold shimmer — hero elements, labels, logo text
        static let goldGradient = LinearGradient(
            stops: [
                .init(color: Color(hex: "#9B7A2A"), location: 0.0),
                .init(color: Color(hex: "#E8C877"), location: 0.45),
                .init(color: Color(hex: "#D4A83C"), location: 0.75),
                .init(color: Color(hex: "#9B7A2A"), location: 1.0)
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

        /// Gold card border shimmer (dark mode)
        static let goldBorderGradient = LinearGradient(
            stops: [
                .init(color: Color(hex: "#C9A84C").opacity(0.30), location: 0.0),
                .init(color: Color.white.opacity(0.05),           location: 0.5),
                .init(color: Color(hex: "#C9A84C").opacity(0.15), location: 1.0)
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
// The signature visual style of JetSetter Pro.
// Dark mode: frosted glass with a gold border shimmer + deep shadow.
// Light mode: clean white with a soft lift shadow.

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Base material (frosted glass in dark, opaque white in light)
                    RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                        .fill(scheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.white))

                    // Inner top-left glow for depth (dark only)
                    if scheme == .dark {
                        RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                            .fill(JetsetterTheme.Colors.cardInnerGlow)
                    }
                }
                // Gold border shimmer (dark) / subtle grey border (light)
                .overlay {
                    RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                        .strokeBorder(
                            scheme == .dark
                                ? AnyShapeStyle(JetsetterTheme.Colors.goldBorderGradient)
                                : AnyShapeStyle(Color.black.opacity(0.06)),
                            lineWidth: 0.6
                        )
                }
                // Deep shadow in dark, soft lift in light
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
    /// Applies the JetSetter Pro executive glass-card appearance.
    func jetCard() -> some View { modifier(CardStyle()) }
}

// MARK: - Gold Text Gradient Modifier

struct GoldTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(JetsetterTheme.Colors.goldGradient)
    }
}

extension View {
    /// Renders text with the signature gold shimmer gradient.
    func goldText() -> some View { modifier(GoldTextModifier()) }
}

// MARK: - Gold Capsule Tag

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
                                    ? Color(hex: "#C9A84C").opacity(0.15)
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
    /// Creates a Color from a CSS hex string — e.g. "#C9A84C" or "C9A84C"
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
