// File: Core/Utilities/VisaRequirements.swift
//
// Visa & entry requirements for US-passport holders entering common
// destinations. Static data — verify via the State Department or destination
// embassy before traveling. Updated 2026-Q1.
//
// Also home to `USStateCodes`, the one US-state table every free-text
// destination matcher uses, so "Indianapolis, IN" is never read as India.

import Foundation

struct VisaRequirement: Identifiable, Hashable {
    var id: String { destination }     // ISO 2-letter destination code
    let destination: String            // ISO code
    let countryName: String
    let flag: String
    let requirementKind: RequirementKind
    let maxStayDays: Int?              // For visa-free / visa-on-arrival; nil for visa-required
    let entryFee: String?              // e.g. "$25 USD" — nil means free / not applicable
    let passportValidityMonths: Int    // Minimum passport validity after arrival
    let blankPagesRequired: Int
    let onwardTicketRequired: Bool
    let additionalNotes: [String]
}

enum RequirementKind: String {
    case visaFree            = "Visa-free"
    case eTA                 = "Electronic travel auth (eTA)"
    case eVisa               = "eVisa (online)"
    case visaOnArrival       = "Visa on arrival"
    case visaRequired        = "Visa required"
    case otherDocsRequired   = "Documentation required"

    var color: String {
        switch self {
        case .visaFree:           return "#1DB97D"
        case .eTA, .eVisa:        return "#3B9EF0"
        case .visaOnArrival:      return "#E8A020"
        case .visaRequired:       return "#E84040"
        case .otherDocsRequired:  return "#7B3FBF"
        }
    }

    var systemImage: String {
        switch self {
        case .visaFree:           return "checkmark.seal.fill"
        case .eTA, .eVisa:        return "globe.americas.fill"
        case .visaOnArrival:      return "airplane.arrival"
        case .visaRequired:       return "doc.text.fill"
        case .otherDocsRequired:  return "exclamationmark.shield.fill"
        }
    }
}

enum VisaRequirements {

    static let forUSPassport: [VisaRequirement] = [
        // ── No visa needed ─────────────────────────────────────────────────
        .init(destination: "JP", countryName: "Japan", flag: "🇯🇵",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 0, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["Passport must be valid for the duration of stay."]),
        .init(destination: "FR", countryName: "France", flag: "🇫🇷",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90 days within any 180-day period across all member states.",
                                "ETIAS authorization required from mid-2025."]),
        .init(destination: "IT", countryName: "Italy", flag: "🇮🇹",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "ES", countryName: "Spain", flag: "🇪🇸",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "DE", countryName: "Germany", flag: "🇩🇪",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "NL", countryName: "Netherlands", flag: "🇳🇱",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "CH", countryName: "Switzerland", flag: "🇨🇭",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "AT", countryName: "Austria", flag: "🇦🇹",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "GR", countryName: "Greece", flag: "🇬🇷",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "PT", countryName: "Portugal", flag: "🇵🇹",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 3, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Schengen Area: 90/180-day rule applies."]),
        .init(destination: "IE", countryName: "Ireland", flag: "🇮🇪",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 0, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["Not part of Schengen. Separate 90-day allowance."]),
        .init(destination: "MX", countryName: "Mexico", flag: "🇲🇽",
              requirementKind: .visaFree, maxStayDays: 180, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["FMM tourist card issued at entry (free if < 7 days, ~$30 otherwise)."]),
        .init(destination: "CR", countryName: "Costa Rica", flag: "🇨🇷",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 1, blankPagesRequired: 1, onwardTicketRequired: true,
              additionalNotes: ["Proof of onward travel mandatory."]),
        .init(destination: "AR", countryName: "Argentina", flag: "🇦🇷",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: []),
        .init(destination: "SG", countryName: "Singapore", flag: "🇸🇬",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: true,
              additionalNotes: ["Pre-arrival SG Arrival Card (free, online)."]),
        .init(destination: "KR", countryName: "South Korea", flag: "🇰🇷",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["K-ETA required if staying > 30 days."]),
        .init(destination: "HK", countryName: "Hong Kong", flag: "🇭🇰",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 1, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: []),
        .init(destination: "TW", countryName: "Taiwan", flag: "🇹🇼",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: true,
              additionalNotes: []),
        .init(destination: "TH", countryName: "Thailand", flag: "🇹🇭",
              requirementKind: .visaFree, maxStayDays: 60, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: true,
              additionalNotes: ["Visa-free stay extended to 60 days as of 2024-Q3."]),
        .init(destination: "MY", countryName: "Malaysia", flag: "🇲🇾",
              requirementKind: .visaFree, maxStayDays: 90, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: []),
        .init(destination: "AE", countryName: "United Arab Emirates", flag: "🇦🇪",
              requirementKind: .visaFree, maxStayDays: 30, entryFee: nil,
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: []),

        // ── eTA / eVisa ────────────────────────────────────────────────────
        .init(destination: "CA", countryName: "Canada", flag: "🇨🇦",
              requirementKind: .eTA, maxStayDays: 180, entryFee: "CAD $7",
              passportValidityMonths: 0, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["eTA required when flying in. Not needed for land/sea entry.",
                                "Apply at canada.ca/eta."]),
        .init(destination: "GB", countryName: "United Kingdom", flag: "🇬🇧",
              requirementKind: .eTA, maxStayDays: 180, entryFee: "£10",
              passportValidityMonths: 0, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["ETA required for US nationals from Jan 2025.",
                                "Apply via UK ETA app or gov.uk."]),
        .init(destination: "AU", countryName: "Australia", flag: "🇦🇺",
              requirementKind: .eTA, maxStayDays: 90, entryFee: "AUD $20",
              passportValidityMonths: 0, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["ETA Subclass 601. Apply via the official Australian ETA app."]),
        .init(destination: "NZ", countryName: "New Zealand", flag: "🇳🇿",
              requirementKind: .eTA, maxStayDays: 90, entryFee: "NZD $23",
              passportValidityMonths: 3, blankPagesRequired: 1, onwardTicketRequired: true,
              additionalNotes: ["NZeTA + IVL (International Visitor Levy) required."]),
        .init(destination: "IN", countryName: "India", flag: "🇮🇳",
              requirementKind: .eVisa, maxStayDays: 30, entryFee: "$25 USD",
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["e-Tourist visa via indianvisaonline.gov.in.",
                                "Apply 4–30 days before travel."]),
        .init(destination: "VN", countryName: "Vietnam", flag: "🇻🇳",
              requirementKind: .eVisa, maxStayDays: 90, entryFee: "$25 USD",
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["evisa.xuatnhapcanh.gov.vn — official portal."]),
        .init(destination: "ID", countryName: "Indonesia", flag: "🇮🇩",
              requirementKind: .visaOnArrival, maxStayDays: 30, entryFee: "IDR 500,000 (~$32)",
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: true,
              additionalNotes: ["Extendable once for 30 more days."]),
        .init(destination: "TR", countryName: "Türkiye", flag: "🇹🇷",
              requirementKind: .eVisa, maxStayDays: 90, entryFee: "$50 USD",
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["evisa.gov.tr — apply online."]),
        .init(destination: "EG", countryName: "Egypt", flag: "🇪🇬",
              requirementKind: .visaOnArrival, maxStayDays: 30, entryFee: "$25 USD",
              passportValidityMonths: 6, blankPagesRequired: 1, onwardTicketRequired: false,
              additionalNotes: ["eVisa also available — sometimes faster."]),
        .init(destination: "KE", countryName: "Kenya", flag: "🇰🇪",
              requirementKind: .eVisa, maxStayDays: 90, entryFee: "$30 USD",
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["eTA required for all visitors from 2024.", "etakenya.go.ke"]),

        // ── Visa required ──────────────────────────────────────────────────
        .init(destination: "CN", countryName: "China", flag: "🇨🇳",
              requirementKind: .visaRequired, maxStayDays: nil, entryFee: "$185 USD",
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["Apply at Chinese consulate, in person.",
                                "10-year multiple-entry tourist visa common.",
                                "Some cities offer 144-hour visa-free transit."]),
        .init(destination: "RU", countryName: "Russia", flag: "🇷🇺",
              requirementKind: .visaRequired, maxStayDays: nil, entryFee: "$160 USD",
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["State Department travel advisory: Do Not Travel."]),
        .init(destination: "BR", countryName: "Brazil", flag: "🇧🇷",
              requirementKind: .eVisa, maxStayDays: 90, entryFee: "$80.90 USD",
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["eVisa requirement reinstated 2025-04. Apply at vfsglobal.com."]),
        .init(destination: "SA", countryName: "Saudi Arabia", flag: "🇸🇦",
              requirementKind: .eVisa, maxStayDays: 90, entryFee: "SAR 480 (~$128)",
              passportValidityMonths: 6, blankPagesRequired: 2, onwardTicketRequired: false,
              additionalNotes: ["e-Visa available via visa.visitsaudi.com."])
    ]

    /// Lookup by country name or ISO code (case-insensitive).
    ///
    /// Matching is deliberately conservative to avoid mis-resolving free-text
    /// destinations (e.g. "San Marino, Italy" or a city that embeds a country
    /// name as a raw substring). In order:
    /// 1. The whole query is an ISO code or a country name ("CA", "Canada").
    /// 2. A US "City, ST" address ("San Francisco, CA") is domestic, so `nil`:
    ///    US passport holders need no visa, and this dataset has no US entry.
    /// 3. A full country name as a contiguous run of words ("Toronto, Canada").
    /// 4. An ISO code, but only when it fills a whole comma-separated slot, is
    ///    written in capitals, and isn't a US state code ("Lyon, FR").
    /// Ambiguous or empty inputs return `nil`.
    ///
    /// Past defect: step 4 used to accept any two-letter token, so "San
    /// Francisco, CA" resolved to Canada (an eTA nudge before a domestic trip)
    /// and "Hotel in Rome" to India.
    static func find(query: String) -> VisaRequirement? {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = raw.lowercased()
        guard !q.isEmpty else { return nil }

        // 1. Exact ISO code or exact country name (a stand-alone "CA" is Canada).
        if let exact = forUSPassport.first(where: {
            $0.destination.lowercased() == q || $0.countryName.lowercased() == q
        }) {
            return exact
        }

        // 2. "City, ST" is a US address, not a country code.
        if USStateCodes.isUSCityState(raw) { return nil }

        // 3. Word-bounded country-name match. A name matches only as a whole
        //    word or a contiguous run of words, never as an arbitrary substring.
        let tokens = q
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return nil }

        let nameMatches = forUSPassport.filter { requirement in
            let nameTokens = requirement.countryName.lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            guard !nameTokens.isEmpty, nameTokens.count <= tokens.count else { return false }
            for start in 0...(tokens.count - nameTokens.count)
            where Array(tokens[start..<(start + nameTokens.count)]) == nameTokens {
                return true
            }
            return false
        }
        if !nameMatches.isEmpty {
            // Only resolve when unambiguous; multiple distinct matches → nil.
            return nameMatches.count == 1 ? nameMatches.first : nil
        }

        // 4. ISO code in a country slot. Lower-case "in", "it", "at" and "my" are
        //    English words, and upper-case state codes belong to US addresses.
        let codeSlots = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count == 2 && $0 == $0.uppercased() && !USStateCodes.contains($0) }
        let codeMatches = forUSPassport.filter { codeSlots.contains($0.destination) }
        return codeMatches.count == 1 ? codeMatches.first : nil
    }
}

// MARK: - US state codes

/// Two-letter US postal codes for the 50 states and DC, shared by every
/// free-text destination matcher (`VisaRequirements`, `TravelEssentialsData`,
/// the Schengen counter) so they agree on what "City, ST" means.
///
/// Many of these collide with ISO country codes: CA (Canada), IN (India),
/// DE (Germany), GA (Gabon), CO (Colombia), AR (Argentina), ID (Indonesia).
/// When one ends a "City, ST" address, it is the US state.
nonisolated enum USStateCodes {

    static let all: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
        "DC"
    ]

    /// True when `code` is a US state (or DC) postal code, in any case.
    static func contains(_ code: String) -> Bool {
        all.contains(code.trimmingCharacters(in: .whitespaces).uppercased())
    }

    /// Trailing components that only restate the country, as in
    /// "Austin, TX, USA".
    private static let usCountrySuffixes: Set<String> = [
        "us", "usa", "u.s.", "u.s.a.", "united states", "united states of america"
    ]

    /// True when `text` reads as a US "City, ST" address: at least two
    /// comma-separated parts, the last of which (ignoring a trailing "USA") is a
    /// state code, optionally followed by a ZIP code ("Wilmington, DE 19801").
    static func isUSCityState(_ text: String) -> Bool {
        var parts = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        while let last = parts.last, parts.count > 2,
              usCountrySuffixes.contains(last.lowercased()) {
            parts.removeLast()
        }
        guard parts.count >= 2, let last = parts.last else { return false }

        let words = last.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let state = words.first, state.count == 2, contains(state) else { return false }
        // Anything after the state must be a ZIP ("19801" or "19801-1234").
        return words.dropFirst().allSatisfy { word in
            !word.isEmpty && word.allSatisfy { $0.isNumber || $0 == "-" }
        }
    }
}
