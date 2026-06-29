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
    //
    // Tokens resolve through the active `JetAppearance` (see JetAppearance.swift):
    //   • .executive — adaptive sky-blue-on-navy (light & dark)
    //   • .cabin     — all-red night palette (airplane mode); state reads by brightness
    //   • .heritage  — leather & gold premium appearance
    //
    // The public accessors below preserve their original names so existing call sites
    // (`JetsetterTheme.Colors.accent`, `.goldGradient`, …) keep working — they now simply
    // dispatch to the appearance the user/airplane mode has selected. New code can also
    // read these per-appearance via the `\.jet` environment palette.

    enum Colors {

        // ── Executive (adaptive light / dark) ───────────────────────────────

        private static let executiveBackground = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#10131E") : UIColor(hex: "#EFF1F8")
        })
        private static let executiveSurface = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#161929") : UIColor(hex: "#FFFFFF")
        })
        private static let executiveSurfaceElevated = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#1D2235") : UIColor(hex: "#F4F5FB")
        })
        private static let executivePrimary = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#1C3555") : UIColor(hex: "#0A2040")
        })
        private static let executiveAccent = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#3B9EF0") : UIColor(hex: "#0055CC")
        })
        private static let executiveBlue = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#4E8FD4") : UIColor(hex: "#1A5FA8")
        })
        private static let executiveSuccess = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#1DB97D") : UIColor(hex: "#0C7A4E")
        })
        private static let executiveWarning = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#E8A020") : UIColor(hex: "#B07010")
        })
        private static let executiveDanger = Color(UIColor { t in
            // Spec palette value, lightened from #E84040 for WCAG AA on dark.
            t.userInterfaceStyle == .dark ? UIColor(hex: "#FF5C5C") : UIColor(hex: "#C42020")
        })
        private static let executiveTextPrimary = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#ECEEF4") : UIColor(hex: "#0A0C18")
        })
        private static let executiveTextSecondary = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#8B92A8") : UIColor(hex: "#52587A")
        })
        private static let executiveSeparator = Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: "#1E2136") : UIColor(hex: "#DDE0EE")
        })

        // ── Per-appearance token resolvers ──────────────────────────────────

        static func backgroundValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveBackground
            case .cabin:     return Color(hex: "#0A0506")
            case .heritage:  return Color(hex: "#160F08")
            }
        }
        static func surfaceValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveSurface
            case .cabin:     return Color(hex: "#170809")
            case .heritage:  return Color(hex: "#1A130C")
            }
        }
        static func surfaceElevatedValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveSurfaceElevated
            case .cabin:     return Color(hex: "#230A0C")
            case .heritage:  return Color(hex: "#291710")
            }
        }
        static func primaryValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executivePrimary
            case .cabin:     return Color(hex: "#4A1513")
            case .heritage:  return Color(hex: "#3F2715")
            }
        }
        static func accentValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveAccent
            case .cabin:     return Color(hex: "#FF453A")
            case .heritage:  return Color(hex: "#DCA646")
            }
        }
        static func blueValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveBlue
            case .cabin:     return Color(hex: "#E0584D")
            case .heritage:  return Color(hex: "#B59B74")
            }
        }
        static func successValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveSuccess
            case .cabin:     return Color(hex: "#E8847B")   // dimmest tier
            case .heritage:  return Color(hex: "#7D8B57")
            }
        }
        static func warningValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveWarning
            case .cabin:     return Color(hex: "#FF8A5C")   // mid tier
            case .heritage:  return Color(hex: "#B07A2E")
            }
        }
        static func dangerValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveDanger
            case .cabin:     return Color(hex: "#FF2D1F")   // brightest tier
            case .heritage:  return Color(hex: "#C85A3A")
            }
        }
        static func textPrimaryValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveTextPrimary
            case .cabin:     return Color(hex: "#FFD2CD")
            case .heritage:  return Color(hex: "#F3E7CE")
            }
        }
        static func textSecondaryValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveTextSecondary
            case .cabin:     return Color(hex: "#C0807A")
            case .heritage:  return Color(hex: "#B59B74")
            }
        }
        static func separatorValue(for a: JetAppearance) -> Color {
            switch a {
            case .executive: return executiveSeparator
            case .cabin:     return Color(hex: "#3A1614")
            case .heritage:  return Color(hex: "#5A4231")
            }
        }

        // ── Public tokens (resolve to the active appearance) ────────────────

        static var background: Color      { backgroundValue(for: JetActiveAppearance.current) }
        static var surface: Color         { surfaceValue(for: JetActiveAppearance.current) }
        static var surfaceElevated: Color { surfaceElevatedValue(for: JetActiveAppearance.current) }
        static var primary: Color         { primaryValue(for: JetActiveAppearance.current) }
        static var accent: Color          { accentValue(for: JetActiveAppearance.current) }
        static var blue: Color            { blueValue(for: JetActiveAppearance.current) }
        static var success: Color         { successValue(for: JetActiveAppearance.current) }
        static var warning: Color         { warningValue(for: JetActiveAppearance.current) }
        static var danger: Color          { dangerValue(for: JetActiveAppearance.current) }
        static var textPrimary: Color     { textPrimaryValue(for: JetActiveAppearance.current) }
        static var textSecondary: Color   { textSecondaryValue(for: JetActiveAppearance.current) }
        static var separator: Color       { separatorValue(for: JetActiveAppearance.current) }

        // ── Gradients ───────────────────────────────────────────────────────

        /// Accent shimmer gradient — hero elements, labels, logo text. (Legacy name
        /// `goldGradient`: the executive palette is sky-blue; cabin is red; heritage is gold.)
        static func accentGradientValue(for a: JetAppearance) -> LinearGradient {
            switch a {
            case .executive:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#1A72E8"), location: 0.0),
                    .init(color: Color(hex: "#5BBAFF"), location: 0.45),
                    .init(color: Color(hex: "#3A9AF0"), location: 0.75),
                    .init(color: Color(hex: "#1A72E8"), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .cabin:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#FF2D1F"), location: 0.0),
                    .init(color: Color(hex: "#FF6A5C"), location: 0.5),
                    .init(color: Color(hex: "#C42822"), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .heritage:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#B07A2E"), location: 0.0),
                    .init(color: Color(hex: "#F6DA94"), location: 0.45),
                    .init(color: Color(hex: "#DCA646"), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }

        /// Deep background gradient — onboarding backgrounds, hero sections.
        static func heroGradientValue(for a: JetAppearance) -> LinearGradient {
            switch a {
            case .executive:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#06070D"), location: 0.0),
                    .init(color: Color(hex: "#0D1425"), location: 0.5),
                    .init(color: Color(hex: "#091530"), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .cabin:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#0A0506"), location: 0.0),
                    .init(color: Color(hex: "#170607"), location: 0.5),
                    .init(color: Color(hex: "#240809"), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .heritage:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#5E3E23"), location: 0.0),
                    .init(color: Color(hex: "#3F2715"), location: 0.52),
                    .init(color: Color(hex: "#291710"), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }

        /// Accent card-border shimmer (dark-on appearances).
        static func borderGradientValue(for a: JetAppearance) -> LinearGradient {
            switch a {
            case .executive:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#3B9EF0").opacity(0.30), location: 0.0),
                    .init(color: Color.white.opacity(0.05),           location: 0.5),
                    .init(color: Color(hex: "#3B9EF0").opacity(0.15), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .cabin:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#FF453A").opacity(0.34), location: 0.0),
                    .init(color: Color.white.opacity(0.04),           location: 0.5),
                    .init(color: Color(hex: "#FF453A").opacity(0.16), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .heritage:
                return LinearGradient(stops: [
                    .init(color: Color(hex: "#F6DA94").opacity(0.40), location: 0.0),
                    .init(color: Color.white.opacity(0.05),           location: 0.5),
                    .init(color: Color(hex: "#DCA646").opacity(0.20), location: 1.0)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }

        /// Accent shimmer gradient — hero elements, labels, logo text.
        static var goldGradient: LinearGradient { accentGradientValue(for: JetActiveAppearance.current) }

        /// Deep dark gradient — onboarding backgrounds, hero sections.
        static var heroGradient: LinearGradient { heroGradientValue(for: JetActiveAppearance.current) }

        /// Accent card border shimmer.
        static var goldBorderGradient: LinearGradient { borderGradientValue(for: JetActiveAppearance.current) }

        /// Subtle card inner glow for depth (dark-on appearances) — appearance-independent.
        static let cardInnerGlow = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.04), location: 0.0),
                .init(color: Color.clear,               location: 1.0)
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

    /// Cabin & Heritage are always dark-on, regardless of the system color scheme.
    private var isDarkSurface: Bool {
        scheme == .dark || JetActiveAppearance.current != .executive
    }

    func body(content: Content) -> some View {
        let darkSurface = isDarkSurface
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                        .fill(darkSurface ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.white))

                    if darkSurface {
                        RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                            .fill(JetsetterTheme.Colors.cardInnerGlow)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: JetsetterTheme.Card.cornerRadius, style: .continuous)
                        .strokeBorder(
                            darkSurface
                                ? AnyShapeStyle(JetsetterTheme.Colors.goldBorderGradient)
                                : AnyShapeStyle(Color.black.opacity(0.06)),
                            lineWidth: 0.6
                        )
                }
                .shadow(
                    color: darkSurface ? .black.opacity(0.55) : .black.opacity(0.06),
                    radius: darkSurface ? 24 : 10,
                    x: 0,
                    y: darkSurface ? 12 : 4
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

    private var isDarkSurface: Bool {
        scheme == .dark || JetActiveAppearance.current != .executive
    }

    func body(content: Content) -> some View {
        let darkSurface = isDarkSurface
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(darkSurface
                          ? AnyShapeStyle(JetsetterTheme.Colors.surfaceElevated)
                          : AnyShapeStyle(Color(UIColor(hex: "#F4F5FB"))))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                darkSurface
                                    ? JetsetterTheme.Colors.accent.opacity(0.18)
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
