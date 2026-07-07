// File: Core/Utilities/VisaRequirements.swift
//
// Visa & entry requirements for US-passport holders entering common
// destinations. Static data — verify via the State Department or destination
// embassy before traveling. Updated 2026-Q1.

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

    /// Lookup by country name, IATA destination, or ISO code (case-insensitive).
    ///
    /// Matching is deliberately conservative to avoid mis-resolving free-text
    /// destinations (e.g. "San Marino, Italy" or a city that embeds a country
    /// name as a raw substring). We prefer exact ISO-code / country-name
    /// matches, then fall back to *word-bounded* token matching so that a
    /// destination string is only mapped to a country when a full token equals
    /// the ISO code or the whole country name appears as a contiguous run of
    /// tokens. Ambiguous or empty inputs return `nil`.
    static func find(query: String) -> VisaRequirement? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }

        // 1. Exact ISO code or exact country name.
        if let exact = forUSPassport.first(where: {
            $0.destination.lowercased() == q || $0.countryName.lowercased() == q
        }) {
            return exact
        }

        // 2. Word-bounded token match. Split the query into tokens on commas
        //    and whitespace; a country matches only if one of its identifiers
        //    (ISO code / country name) appears as a whole token or a contiguous
        //    run of tokens — never as an arbitrary substring.
        let tokens = q
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return nil }

        let matches = forUSPassport.filter { requirement in
            let code = requirement.destination.lowercased()
            let nameTokens = requirement.countryName.lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)

            // ISO code must equal a full token (avoids "in" matching inside a word).
            if tokens.contains(code) { return true }

            // Country name must appear as a contiguous run of query tokens.
            guard !nameTokens.isEmpty, nameTokens.count <= tokens.count else { return false }
            for start in 0...(tokens.count - nameTokens.count)
            where Array(tokens[start..<(start + nameTokens.count)]) == nameTokens {
                return true
            }
            return false
        }

        // Only resolve when unambiguous; multiple distinct matches → nil.
        return matches.count == 1 ? matches.first : nil
    }
}
