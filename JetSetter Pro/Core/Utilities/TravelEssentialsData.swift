// File: Core/Utilities/TravelEssentialsData.swift
//
// Static country dataset: emergency numbers, tipping etiquette, electrical
// plug standards, water safety, scams, and useful local phrases. Bundled so
// Travel Essentials works offline.

import Foundation

struct CountryEssentials: Identifiable, Hashable {
    let id: String           // ISO 2-letter code
    let name: String
    let flagEmoji: String
    let emergency: EmergencyNumbers
    let tipping: TippingGuide
    let electrical: ElectricalGuide
    let waterSafe: Bool
    let waterNote: String?
    let commonScams: [String]
    let phrases: [LocalPhrase]
}

struct EmergencyNumbers: Hashable {
    let police: String
    let ambulance: String
    let fire: String
    let general: String?   // e.g. 112 in EU; nil when each service has its own
    let touristHotline: String?
}

struct TippingGuide: Hashable {
    let restaurantPercent: String     // "15–20%", "10%", "Not expected"
    let taxiPercent: String
    let hotelPerDay: String
    let note: String?
}

struct ElectricalGuide: Hashable {
    let plugTypes: [String]   // ["A", "B"] or ["C", "F"]
    let voltage: String       // "120V / 60Hz"
    let needsAdapterForUS: Bool
}

struct LocalPhrase: Hashable {
    let english: String
    let local: String
    let pronunciation: String?
}

// MARK: - Catalog

enum TravelEssentialsData {

    static let countries: [CountryEssentials] = [
        japan, france, italy, spain, unitedKingdom, germany, netherlands,
        switzerland, austria, greece, portugal, ireland,
        usa, canada, mexico, brazil, argentina,
        thailand, vietnam, singapore, southKorea, china, hongKong, taiwan,
        india, uae, qatar, israel, turkey,
        australia, newZealand,
        southAfrica, kenya, egypt, morocco
    ]

    /// Looks up a country by name (case-insensitive), ISO code, city string, or
    /// airport code. Returns `nil` when nothing confidently matches — callers
    /// must NOT fall back to an arbitrary country (wrong emergency/water data is
    /// dangerous); show a "pick your destination" prompt instead.
    static func find(query: String) -> CountryEssentials? {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let q = raw.lowercased()

        // 1. Exact ISO code or country name.
        if let exact = countries.first(where: { $0.id.lowercased() == q || $0.name.lowercased() == q }) {
            return exact
        }

        // 2. Airport code (e.g. "ATL", "CDG", "NRT-HND") → country.
        //    Take the first alphabetic token and try it as an IATA code.
        let firstToken = q
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first { !$0.isEmpty } ?? q
        if firstToken.count == 3,
           firstToken.allSatisfy({ $0.isLetter }),
           let iso = airportCodeToCountry[firstToken],
           let match = countries.first(where: { $0.id == iso }) {
            return match
        }

        // 3. City string with a trailing country/region token after a comma
        //    (e.g. "Paris, France" or "Atlanta, GA"). Try each comma-separated
        //    token from the end, matching country names or codes.
        let tokens = q
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for token in tokens.reversed() {
            if let byCode = countries.first(where: { $0.id.lowercased() == token }) {
                return byCode
            }
            if let byName = countries.first(where: { $0.name.lowercased() == token }) {
                return byName
            }
            if let usState = usStateAbbreviations[token],
               usState,
               let usa = countries.first(where: { $0.id == "US" }) {
                return usa
            }
        }

        // 4. Last resort: whole-word match against country names only. Splitting
        //    the query on word boundaries and comparing full words (never raw
        //    `contains`) avoids matching a country name that only appears as a
        //    fragment of an unrelated place — e.g. "Indiana"/"Indianapolis" must
        //    NOT resolve to India, nor "Chinatown" to China. Multi-word country
        //    names (e.g. "United Kingdom") are matched as an ordered run of words.
        let words = q
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return countries.first { country in
            let nameWords = country.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            guard !nameWords.isEmpty, nameWords.count <= words.count else { return false }
            // Look for `nameWords` as a contiguous run within `words`.
            for start in 0...(words.count - nameWords.count) where Array(words[start..<start + nameWords.count]) == nameWords {
                return true
            }
            return false
        }
    }

    /// Minimal IATA airport-code → ISO-country map covering the destinations in
    /// this catalog. Not exhaustive by design; unmatched codes correctly fall
    /// through to the neutral empty state rather than guessing.
    private static let airportCodeToCountry: [String: String] = [
        // United States
        "atl": "US", "jfk": "US", "lax": "US", "ord": "US", "sfo": "US",
        "mia": "US", "sea": "US", "bos": "US", "dfw": "US", "las": "US",
        "iad": "US", "dca": "US", "ewr": "US", "lga": "US",
        // Canada
        "yyz": "CA", "yvr": "CA", "yul": "CA",
        // Mexico
        "mex": "MX", "cun": "MX",
        // United Kingdom
        "lhr": "GB", "lgw": "GB", "lcy": "GB", "man": "GB", "edi": "GB",
        // France
        "cdg": "FR", "ory": "FR", "nce": "FR",
        // Italy
        "fco": "IT", "mxp": "IT", "vce": "IT",
        // Spain
        "mad": "ES", "bcn": "ES",
        // Germany
        "fra": "DE", "muc": "DE", "ber": "DE",
        // Netherlands
        "ams": "NL",
        // Switzerland
        "zrh": "CH", "gva": "CH",
        // Austria
        "vie": "AT",
        // Greece
        "ath": "GR",
        // Portugal
        "lis": "PT", "opo": "PT",
        // Ireland
        "dub": "IE",
        // Brazil
        "gru": "BR", "gig": "BR",
        // Argentina
        "eze": "AR",
        // Thailand
        "bkk": "TH", "hkt": "TH",
        // Vietnam
        "sgn": "VN", "han": "VN",
        // Singapore
        "sin": "SG",
        // South Korea
        "icn": "KR",
        // China
        "pek": "CN", "pvg": "CN", "can": "CN",
        // Hong Kong
        "hkg": "HK",
        // Taiwan
        "tpe": "TW",
        // India
        "del": "IN", "bom": "IN",
        // United Arab Emirates
        "dxb": "AE", "auh": "AE",
        // Qatar
        "doh": "QA",
        // Israel
        "tlv": "IL",
        // Türkiye
        "ist": "TR", "saw": "TR",
        // Australia
        "syd": "AU", "mel": "AU",
        // New Zealand
        "akl": "NZ",
        // South Africa
        "jnb": "ZA", "cpt": "ZA",
        // Kenya
        "nbo": "KE",
        // Egypt
        "cai": "EG",
        // Morocco
        "rak": "MA", "cmn": "MA",
        // Japan
        "nrt": "JP", "hnd": "JP", "kix": "JP"
    ]

    /// US state abbreviations, so "Atlanta, GA" resolves to the United States
    /// rather than falling through to an unrelated country.
    private static let usStateAbbreviations: [String: Bool] = [
        "al": true, "ak": true, "az": true, "ar": true, "ca": true, "co": true,
        "ct": true, "de": true, "fl": true, "ga": true, "hi": true, "id": true,
        "il": true, "in": true, "ia": true, "ks": true, "ky": true, "la": true,
        "me": true, "md": true, "ma": true, "mi": true, "mn": true, "ms": true,
        "mo": true, "mt": true, "ne": true, "nv": true, "nh": true, "nj": true,
        "nm": true, "ny": true, "nc": true, "nd": true, "oh": true, "ok": true,
        "or": true, "pa": true, "ri": true, "sc": true, "sd": true, "tn": true,
        "tx": true, "ut": true, "vt": true, "va": true, "wa": true, "wv": true,
        "wi": true, "wy": true, "dc": true
    ]
}

// MARK: - Country entries

private extension TravelEssentialsData {

    static let japan = CountryEssentials(
        id: "JP", name: "Japan", flagEmoji: "🇯🇵",
        emergency: .init(police: "110", ambulance: "119", fire: "119", general: nil, touristHotline: "050-3816-2787"),
        tipping: .init(
            restaurantPercent: "Not expected",
            taxiPercent: "Not expected",
            hotelPerDay: "Not expected",
            note: "Tipping can be considered rude. Excellent service is the standard."
        ),
        electrical: .init(plugTypes: ["A", "B"], voltage: "100V / 50–60Hz", needsAdapterForUS: false),
        waterSafe: true, waterNote: "Tap water is safe and tasty throughout Japan.",
        commonScams: [
            "Overpriced 'snack bar' clip joints in Roppongi/Kabukichō",
            "Touts offering 'introductions' to restaurants — walk past"
        ],
        phrases: [
            .init(english: "Thank you", local: "ありがとう", pronunciation: "arigatō"),
            .init(english: "Excuse me", local: "すみません", pronunciation: "sumimasen"),
            .init(english: "Yes / No", local: "はい / いいえ", pronunciation: "hai / iie"),
            .init(english: "How much?", local: "いくらですか？", pronunciation: "ikura desu ka"),
            .init(english: "Where is the bathroom?", local: "トイレはどこですか？", pronunciation: "toire wa doko desu ka")
        ]
    )

    static let france = CountryEssentials(
        id: "FR", name: "France", flagEmoji: "🇫🇷",
        emergency: .init(police: "17", ambulance: "15", fire: "18", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "Service compris — round up or +5%",
            taxiPercent: "Round up to nearest €",
            hotelPerDay: "€1–2",
            note: "A 15% service charge is included by law. Extra tips are appreciated but not expected."
        ),
        electrical: .init(plugTypes: ["C", "E"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Tap water is safe everywhere.",
        commonScams: [
            "Petition scams near tourist sites (Eiffel Tower, Sacré-Cœur)",
            "Gold ring 'find' scam along the Seine",
            "Friendship bracelet hustlers at Montmartre"
        ],
        phrases: [
            .init(english: "Hello", local: "Bonjour", pronunciation: "bohn-zhoor"),
            .init(english: "Thank you", local: "Merci", pronunciation: "mehr-see"),
            .init(english: "Please", local: "S'il vous plaît", pronunciation: "seel voo pleh"),
            .init(english: "Excuse me", local: "Excusez-moi", pronunciation: "ehks-koo-zay mwah"),
            .init(english: "Do you speak English?", local: "Parlez-vous anglais?", pronunciation: "par-lay-voo on-gleh")
        ]
    )

    static let italy = CountryEssentials(
        id: "IT", name: "Italy", flagEmoji: "🇮🇹",
        emergency: .init(police: "113", ambulance: "118", fire: "115", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "Round up or 5–10%",
            taxiPercent: "Round up",
            hotelPerDay: "€1–2",
            note: "Coperto (cover charge) is common; tipping on top is optional."
        ),
        electrical: .init(plugTypes: ["C", "F", "L"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Tap water is safe; look for 'acqua non potabile' signs on fountains that aren't.",
        commonScams: [
            "Fake police asking to check your wallet",
            "Aggressive flower/trinket sellers in Rome",
            "Inflated taxi fares — insist on the meter"
        ],
        phrases: [
            .init(english: "Hello / Goodbye", local: "Ciao", pronunciation: "chow"),
            .init(english: "Thank you", local: "Grazie", pronunciation: "grah-tsee-eh"),
            .init(english: "Please", local: "Per favore", pronunciation: "pehr fah-voh-reh"),
            .init(english: "The check, please", local: "Il conto, per favore", pronunciation: "eel kohn-toh"),
            .init(english: "Where is...?", local: "Dov'è...?", pronunciation: "doh-veh")
        ]
    )

    static let spain = CountryEssentials(
        id: "ES", name: "Spain", flagEmoji: "🇪🇸",
        emergency: .init(police: "091", ambulance: "061", fire: "080", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "5–10% if no service charge",
            taxiPercent: "Round up",
            hotelPerDay: "€1",
            note: "Tipping is modest. Locals often just round up."
        ),
        electrical: .init(plugTypes: ["C", "F"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe in major cities; bottled water common in tourist areas.",
        commonScams: [
            "Pickpockets on Las Ramblas and Metro in Barcelona",
            "Distraction scams ('look at this bird/map')",
            "Card-skimming ATMs — use bank-branded machines"
        ],
        phrases: [
            .init(english: "Hello", local: "Hola", pronunciation: "oh-lah"),
            .init(english: "Thank you", local: "Gracias", pronunciation: "grah-syas"),
            .init(english: "Please", local: "Por favor", pronunciation: "por fah-vor"),
            .init(english: "How much?", local: "¿Cuánto cuesta?", pronunciation: "kwan-toh kwes-tah"),
            .init(english: "Help!", local: "¡Ayuda!", pronunciation: "ah-yoo-dah")
        ]
    )

    static let unitedKingdom = CountryEssentials(
        id: "GB", name: "United Kingdom", flagEmoji: "🇬🇧",
        emergency: .init(police: "999", ambulance: "999", fire: "999", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "10–12.5% (often added automatically)",
            taxiPercent: "10%",
            hotelPerDay: "£1–2",
            note: "Check if service is included before tipping. Tipping in pubs is unusual."
        ),
        electrical: .init(plugTypes: ["G"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe everywhere.",
        commonScams: [
            "Unlicensed minicabs at airports — use black cabs or pre-booked",
            "Fake 'card declined' tap at restaurants — watch your card"
        ],
        phrases: [
            .init(english: "Cheers (thanks)", local: "Cheers", pronunciation: "cheers"),
            .init(english: "Sorry", local: "Sorry", pronunciation: "sor-ee"),
            .init(english: "Mind the gap", local: "Mind the gap", pronunciation: "—")
        ]
    )

    static let germany = CountryEssentials(
        id: "DE", name: "Germany", flagEmoji: "🇩🇪",
        emergency: .init(police: "110", ambulance: "112", fire: "112", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "5–10%, round up",
            taxiPercent: "Round up",
            hotelPerDay: "€1–2",
            note: "Tell the server the total amount you want to pay (including tip) when handing over cash."
        ),
        electrical: .init(plugTypes: ["C", "F"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Excellent tap water nationwide.",
        commonScams: [
            "Gambling 'shell game' scams around Brandenburg Gate",
            "Train ticket touts — buy from machines or counters only"
        ],
        phrases: [
            .init(english: "Hello", local: "Hallo", pronunciation: "hah-loh"),
            .init(english: "Thank you", local: "Danke", pronunciation: "dahn-keh"),
            .init(english: "Please / You're welcome", local: "Bitte", pronunciation: "bit-teh"),
            .init(english: "The bill, please", local: "Die Rechnung, bitte", pronunciation: "dee rekh-noong bit-teh")
        ]
    )

    static let netherlands = CountryEssentials(
        id: "NL", name: "Netherlands", flagEmoji: "🇳🇱",
        emergency: .init(police: "112", ambulance: "112", fire: "112", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "5–10%, round up",
            taxiPercent: "Round up",
            hotelPerDay: "€1",
            note: "Service is included; tipping is optional and modest."
        ),
        electrical: .init(plugTypes: ["C", "F"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe everywhere.",
        commonScams: ["Pickpockets in Centraal Station and Red Light District"],
        phrases: [
            .init(english: "Hello", local: "Hallo", pronunciation: "hah-loh"),
            .init(english: "Thank you", local: "Dank je / Dank u", pronunciation: "dank yuh / dank oo"),
            .init(english: "Sorry", local: "Sorry / Pardon", pronunciation: "sor-ee")
        ]
    )

    static let switzerland = CountryEssentials(
        id: "CH", name: "Switzerland", flagEmoji: "🇨🇭",
        emergency: .init(police: "117", ambulance: "144", fire: "118", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "Round up or 5–10%",
            taxiPercent: "Round up",
            hotelPerDay: "CHF 1–2",
            note: "Service is included by law. Tips are appreciated but small."
        ),
        electrical: .init(plugTypes: ["C", "J"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Outstanding tap water — fountains in cities are usually drinkable.",
        commonScams: [],
        phrases: [
            .init(english: "Hello (Zurich/Bern)", local: "Grüezi", pronunciation: "groo-ets-ee"),
            .init(english: "Thank you", local: "Danke", pronunciation: "dahn-keh")
        ]
    )

    static let austria = CountryEssentials(
        id: "AT", name: "Austria", flagEmoji: "🇦🇹",
        emergency: .init(police: "133", ambulance: "144", fire: "122", general: "112", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "5–10%, hand to server directly",
            taxiPercent: "Round up",
            hotelPerDay: "€1–2",
            note: nil
        ),
        electrical: .init(plugTypes: ["C", "F"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe.",
        commonScams: ["Fake concert ticket sellers in Vienna (period-costume scammers)"],
        phrases: [
            .init(english: "Hello", local: "Grüß Gott", pronunciation: "groos got"),
            .init(english: "Thank you", local: "Danke", pronunciation: "dahn-keh")
        ]
    )

    static let greece = CountryEssentials(
        id: "GR", name: "Greece", flagEmoji: "🇬🇷",
        emergency: .init(police: "100", ambulance: "166", fire: "199", general: "112", touristHotline: "1571"),
        tipping: .init(
            restaurantPercent: "5–10%",
            taxiPercent: "Round up",
            hotelPerDay: "€1–2",
            note: nil
        ),
        electrical: .init(plugTypes: ["C", "F"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe on the mainland; bottled water is wiser on smaller islands.",
        commonScams: ["Inflated taxi fares from Athens airport — insist on the meter"],
        phrases: [
            .init(english: "Hello", local: "Γειά σας", pronunciation: "yah sas"),
            .init(english: "Thank you", local: "Ευχαριστώ", pronunciation: "ef-kha-ree-stoh")
        ]
    )

    static let portugal = CountryEssentials(
        id: "PT", name: "Portugal", flagEmoji: "🇵🇹",
        emergency: .init(police: "112", ambulance: "112", fire: "112", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "5–10%", taxiPercent: "Round up", hotelPerDay: "€1", note: nil),
        electrical: .init(plugTypes: ["C", "F"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe.",
        commonScams: [],
        phrases: [
            .init(english: "Hello", local: "Olá", pronunciation: "oh-lah"),
            .init(english: "Thank you", local: "Obrigado / Obrigada", pronunciation: "oh-bree-gah-doh")
        ]
    )

    static let ireland = CountryEssentials(
        id: "IE", name: "Ireland", flagEmoji: "🇮🇪",
        emergency: .init(police: "999", ambulance: "999", fire: "999", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "10–15%", taxiPercent: "Round up", hotelPerDay: "€1–2", note: "Not expected in pubs."),
        electrical: .init(plugTypes: ["G"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe.",
        commonScams: [],
        phrases: [
            .init(english: "Cheers (thanks)", local: "Cheers", pronunciation: "cheers"),
            .init(english: "Hello", local: "Dia dhuit", pronunciation: "jee-ah gwit")
        ]
    )

    static let usa = CountryEssentials(
        id: "US", name: "United States", flagEmoji: "🇺🇸",
        emergency: .init(police: "911", ambulance: "911", fire: "911", general: "911", touristHotline: nil),
        tipping: .init(
            restaurantPercent: "18–22%",
            taxiPercent: "15–20%",
            hotelPerDay: "$2–5 housekeeping, $1–2 bellhop",
            note: "Tipping is essential — service workers earn below minimum wage and rely on tips."
        ),
        electrical: .init(plugTypes: ["A", "B"], voltage: "120V / 60Hz", needsAdapterForUS: false),
        waterSafe: true, waterNote: "Safe everywhere; some areas have unappealing taste.",
        commonScams: ["Times Square costumed characters demanding tips", "Aggressive 'CD artists' in tourist areas"],
        phrases: []
    )

    static let canada = CountryEssentials(
        id: "CA", name: "Canada", flagEmoji: "🇨🇦",
        emergency: .init(police: "911", ambulance: "911", fire: "911", general: "911", touristHotline: nil),
        tipping: .init(restaurantPercent: "15–20%", taxiPercent: "15%", hotelPerDay: "$2–5 CAD", note: nil),
        electrical: .init(plugTypes: ["A", "B"], voltage: "120V / 60Hz", needsAdapterForUS: false),
        waterSafe: true, waterNote: "Safe.",
        commonScams: [],
        phrases: [.init(english: "Hello (French Canada)", local: "Bonjour", pronunciation: "bohn-zhoor")]
    )

    static let mexico = CountryEssentials(
        id: "MX", name: "Mexico", flagEmoji: "🇲🇽",
        emergency: .init(police: "911", ambulance: "911", fire: "911", general: "911", touristHotline: "078"),
        tipping: .init(restaurantPercent: "10–15%", taxiPercent: "Round up", hotelPerDay: "$1–2 USD", note: nil),
        electrical: .init(plugTypes: ["A", "B"], voltage: "127V / 60Hz", needsAdapterForUS: false),
        waterSafe: false, waterNote: "Drink bottled water; avoid ice from street vendors.",
        commonScams: [
            "Inflated 'turista' taxi rates — use Uber or pre-paid airport taxis",
            "Distraction scams in Zócalo (CDMX)"
        ],
        phrases: [
            .init(english: "Hello", local: "Hola", pronunciation: "oh-lah"),
            .init(english: "Thank you", local: "Gracias", pronunciation: "grah-syas"),
            .init(english: "How much?", local: "¿Cuánto cuesta?", pronunciation: "kwan-toh kwes-tah")
        ]
    )

    static let brazil = CountryEssentials(
        id: "BR", name: "Brazil", flagEmoji: "🇧🇷",
        emergency: .init(police: "190", ambulance: "192", fire: "193", general: nil, touristHotline: nil),
        tipping: .init(restaurantPercent: "10% (often included)", taxiPercent: "Round up", hotelPerDay: "R$5–10", note: nil),
        electrical: .init(plugTypes: ["C", "N"], voltage: "127V or 220V / 60Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Stick to bottled water.",
        commonScams: ["Rio: avoid showing valuables on the beach. Use ride-shares, not random taxis."],
        phrases: [
            .init(english: "Hello", local: "Olá", pronunciation: "oh-lah"),
            .init(english: "Thank you", local: "Obrigado / Obrigada", pronunciation: "oh-bree-gah-doh")
        ]
    )

    static let argentina = CountryEssentials(
        id: "AR", name: "Argentina", flagEmoji: "🇦🇷",
        emergency: .init(police: "911", ambulance: "107", fire: "100", general: "911", touristHotline: nil),
        tipping: .init(restaurantPercent: "10%", taxiPercent: "Round up", hotelPerDay: "$1–2 USD", note: nil),
        electrical: .init(plugTypes: ["C", "I"], voltage: "220V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe in Buenos Aires; bottled elsewhere.",
        commonScams: ["'Mustard' splash distraction pickpocket in Buenos Aires"],
        phrases: [
            .init(english: "Hello", local: "Hola", pronunciation: "oh-lah"),
            .init(english: "Thank you", local: "Gracias", pronunciation: "grah-syas")
        ]
    )

    static let thailand = CountryEssentials(
        id: "TH", name: "Thailand", flagEmoji: "🇹🇭",
        emergency: .init(police: "191", ambulance: "1669", fire: "199", general: nil, touristHotline: "1155"),
        tipping: .init(restaurantPercent: "5–10%", taxiPercent: "Round up", hotelPerDay: "20–50 THB", note: nil),
        electrical: .init(plugTypes: ["A", "B", "C"], voltage: "220V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Drink bottled water everywhere.",
        commonScams: [
            "'Grand Palace closed' tuk-tuk scam — go straight to the entrance",
            "Gem and tailor scams",
            "Jet ski 'damage' shakedowns in Phuket"
        ],
        phrases: [
            .init(english: "Hello", local: "สวัสดี", pronunciation: "sah-wah-dee"),
            .init(english: "Thank you", local: "ขอบคุณ", pronunciation: "kop-kun"),
            .init(english: "How much?", local: "เท่าไหร่", pronunciation: "tao-rai")
        ]
    )

    static let vietnam = CountryEssentials(
        id: "VN", name: "Vietnam", flagEmoji: "🇻🇳",
        emergency: .init(police: "113", ambulance: "115", fire: "114", general: nil, touristHotline: nil),
        tipping: .init(restaurantPercent: "5–10%", taxiPercent: "Round up", hotelPerDay: "$1–2 USD", note: nil),
        electrical: .init(plugTypes: ["A", "C", "D"], voltage: "220V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Bottled only.",
        commonScams: ["Fake taxis at Hanoi airport — use Grab or pre-booked"],
        phrases: [
            .init(english: "Hello", local: "Xin chào", pronunciation: "sin chow"),
            .init(english: "Thank you", local: "Cảm ơn", pronunciation: "gahm uhn")
        ]
    )

    static let singapore = CountryEssentials(
        id: "SG", name: "Singapore", flagEmoji: "🇸🇬",
        emergency: .init(police: "999", ambulance: "995", fire: "995", general: nil, touristHotline: nil),
        tipping: .init(restaurantPercent: "Service charge included — extra optional", taxiPercent: "Not expected", hotelPerDay: "Not expected", note: "Tipping is discouraged at Changi Airport."),
        electrical: .init(plugTypes: ["G"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe and excellent.",
        commonScams: [],
        phrases: [.init(english: "Thank you (Mandarin)", local: "谢谢", pronunciation: "shieh-shieh")]
    )

    static let southKorea = CountryEssentials(
        id: "KR", name: "South Korea", flagEmoji: "🇰🇷",
        emergency: .init(police: "112", ambulance: "119", fire: "119", general: nil, touristHotline: "1330"),
        tipping: .init(restaurantPercent: "Not expected", taxiPercent: "Not expected", hotelPerDay: "Not expected", note: "Tipping is not part of the culture; it may even be refused."),
        electrical: .init(plugTypes: ["C", "F"], voltage: "220V / 60Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Generally safe; bottled water is the norm.",
        commonScams: ["Itaewon: avoid overpriced 'club tickets'"],
        phrases: [
            .init(english: "Hello", local: "안녕하세요", pronunciation: "an-nyeong-ha-se-yo"),
            .init(english: "Thank you", local: "감사합니다", pronunciation: "kam-sah-ham-ni-da")
        ]
    )

    static let china = CountryEssentials(
        id: "CN", name: "China", flagEmoji: "🇨🇳",
        emergency: .init(police: "110", ambulance: "120", fire: "119", general: nil, touristHotline: "12301"),
        tipping: .init(restaurantPercent: "Not expected", taxiPercent: "Not expected", hotelPerDay: "Not expected", note: "Tipping is not customary outside high-end hotels."),
        electrical: .init(plugTypes: ["A", "C", "I"], voltage: "220V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Drink bottled water only.",
        commonScams: [
            "'Tea house' invitations from friendly strangers in Beijing/Shanghai",
            "Art student gallery scams"
        ],
        phrases: [
            .init(english: "Hello", local: "你好", pronunciation: "ni-hao"),
            .init(english: "Thank you", local: "谢谢", pronunciation: "shieh-shieh"),
            .init(english: "How much?", local: "多少钱", pronunciation: "duo-shao-chien")
        ]
    )

    static let hongKong = CountryEssentials(
        id: "HK", name: "Hong Kong", flagEmoji: "🇭🇰",
        emergency: .init(police: "999", ambulance: "999", fire: "999", general: "999", touristHotline: nil),
        tipping: .init(restaurantPercent: "10% (often included)", taxiPercent: "Round up", hotelPerDay: "HK$10–20", note: nil),
        electrical: .init(plugTypes: ["G"], voltage: "220V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe.",
        commonScams: [],
        phrases: [.init(english: "Hello", local: "你好", pronunciation: "ni-hao")]
    )

    static let taiwan = CountryEssentials(
        id: "TW", name: "Taiwan", flagEmoji: "🇹🇼",
        emergency: .init(police: "110", ambulance: "119", fire: "119", general: nil, touristHotline: "0800-011-765"),
        tipping: .init(restaurantPercent: "Not expected", taxiPercent: "Not expected", hotelPerDay: "Not expected", note: nil),
        electrical: .init(plugTypes: ["A", "B"], voltage: "110V / 60Hz", needsAdapterForUS: false),
        waterSafe: true, waterNote: "Safe in Taipei; bottled elsewhere.",
        commonScams: [],
        phrases: [
            .init(english: "Hello", local: "你好", pronunciation: "ni-hao"),
            .init(english: "Thank you", local: "謝謝", pronunciation: "shieh-shieh")
        ]
    )

    static let india = CountryEssentials(
        id: "IN", name: "India", flagEmoji: "🇮🇳",
        emergency: .init(police: "100", ambulance: "102", fire: "101", general: "112", touristHotline: "1363"),
        tipping: .init(restaurantPercent: "10%", taxiPercent: "Round up", hotelPerDay: "₹100", note: "Service tax often added at restaurants."),
        electrical: .init(plugTypes: ["C", "D", "M"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Bottled or filtered water only — including for brushing teeth.",
        commonScams: [
            "Inflated tuk-tuk fares — agree price first or use Ola/Uber",
            "'Closed' hotel/attraction redirects",
            "Train ticket office scams in Delhi — only use official IRCTC counters"
        ],
        phrases: [
            .init(english: "Hello", local: "नमस्ते", pronunciation: "nuh-muh-stay"),
            .init(english: "Thank you", local: "धन्यवाद", pronunciation: "dhan-yuh-vahd")
        ]
    )

    static let uae = CountryEssentials(
        id: "AE", name: "United Arab Emirates", flagEmoji: "🇦🇪",
        emergency: .init(police: "999", ambulance: "998", fire: "997", general: "999", touristHotline: nil),
        tipping: .init(restaurantPercent: "10% (often included as service)", taxiPercent: "Round up", hotelPerDay: "AED 5–10", note: nil),
        electrical: .init(plugTypes: ["G"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe; bottled is common.",
        commonScams: ["Unlicensed gold/perfume shops with inflated prices"],
        phrases: [
            .init(english: "Hello", local: "مرحبا", pronunciation: "mar-ha-ban"),
            .init(english: "Thank you", local: "شكرا", pronunciation: "shoo-kran")
        ]
    )

    static let qatar = CountryEssentials(
        id: "QA", name: "Qatar", flagEmoji: "🇶🇦",
        emergency: .init(police: "999", ambulance: "999", fire: "999", general: "999", touristHotline: nil),
        tipping: .init(restaurantPercent: "10%", taxiPercent: "Round up", hotelPerDay: "QAR 10", note: nil),
        electrical: .init(plugTypes: ["G"], voltage: "240V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe.",
        commonScams: [],
        phrases: [.init(english: "Thank you", local: "شكرا", pronunciation: "shoo-kran")]
    )

    static let israel = CountryEssentials(
        id: "IL", name: "Israel", flagEmoji: "🇮🇱",
        emergency: .init(police: "100", ambulance: "101", fire: "102", general: nil, touristHotline: nil),
        tipping: .init(restaurantPercent: "10–15%", taxiPercent: "Not expected", hotelPerDay: "20 ILS", note: nil),
        electrical: .init(plugTypes: ["C", "H", "M"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe.",
        commonScams: ["Old city Jerusalem: 'guides' offering unsolicited tours"],
        phrases: [
            .init(english: "Hello / Goodbye / Peace", local: "שלום", pronunciation: "sha-lom"),
            .init(english: "Thank you", local: "תודה", pronunciation: "to-da")
        ]
    )

    static let turkey = CountryEssentials(
        id: "TR", name: "Türkiye", flagEmoji: "🇹🇷",
        emergency: .init(police: "155", ambulance: "112", fire: "110", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "10–15%", taxiPercent: "Round up", hotelPerDay: "₺20", note: nil),
        electrical: .init(plugTypes: ["C", "F"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Drink bottled water; tap water is treated but unfamiliar to many travelers.",
        commonScams: [
            "Istanbul: 'friendly local' invites to overpriced clubs",
            "Inflated taxi fares — insist on the meter"
        ],
        phrases: [
            .init(english: "Hello", local: "Merhaba", pronunciation: "mehr-ha-ba"),
            .init(english: "Thank you", local: "Teşekkür ederim", pronunciation: "teh-shek-kur eh-deh-rim")
        ]
    )

    static let australia = CountryEssentials(
        id: "AU", name: "Australia", flagEmoji: "🇦🇺",
        emergency: .init(police: "000", ambulance: "000", fire: "000", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "Not expected; 10% for great service", taxiPercent: "Not expected", hotelPerDay: "Not expected", note: "Minimum wage is high; tipping is genuinely optional."),
        electrical: .init(plugTypes: ["I"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe everywhere.",
        commonScams: [],
        phrases: [.init(english: "Thanks", local: "Cheers", pronunciation: "cheers")]
    )

    static let newZealand = CountryEssentials(
        id: "NZ", name: "New Zealand", flagEmoji: "🇳🇿",
        emergency: .init(police: "111", ambulance: "111", fire: "111", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "Not expected", taxiPercent: "Not expected", hotelPerDay: "Not expected", note: nil),
        electrical: .init(plugTypes: ["I"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Excellent tap water.",
        commonScams: [],
        phrases: [.init(english: "Hello (Māori)", local: "Kia ora", pronunciation: "kee-ah or-ah")]
    )

    static let southAfrica = CountryEssentials(
        id: "ZA", name: "South Africa", flagEmoji: "🇿🇦",
        emergency: .init(police: "10111", ambulance: "10177", fire: "10177", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "10–15%", taxiPercent: "10%", hotelPerDay: "R20", note: "Petrol attendants and car guards typically expect R5–10."),
        electrical: .init(plugTypes: ["D", "M", "N"], voltage: "230V / 50Hz", needsAdapterForUS: true),
        waterSafe: true, waterNote: "Safe in major cities.",
        commonScams: ["Avoid showing valuables. Use registered taxi services or Uber."],
        phrases: [.init(english: "Hello", local: "Hello / Sawubona (Zulu)", pronunciation: "sah-woo-bo-na")]
    )

    static let kenya = CountryEssentials(
        id: "KE", name: "Kenya", flagEmoji: "🇰🇪",
        emergency: .init(police: "999", ambulance: "999", fire: "999", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "10%", taxiPercent: "Round up", hotelPerDay: "$2–5 USD", note: "Safari guides traditionally receive $10–20/day per guest."),
        electrical: .init(plugTypes: ["G"], voltage: "240V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Bottled only.",
        commonScams: [],
        phrases: [
            .init(english: "Hello (Swahili)", local: "Jambo", pronunciation: "jam-boh"),
            .init(english: "Thank you", local: "Asante", pronunciation: "ah-san-teh")
        ]
    )

    static let egypt = CountryEssentials(
        id: "EG", name: "Egypt", flagEmoji: "🇪🇬",
        emergency: .init(police: "122", ambulance: "123", fire: "180", general: nil, touristHotline: "126"),
        tipping: .init(restaurantPercent: "10%", taxiPercent: "Round up", hotelPerDay: "EGP 20", note: "'Baksheesh' (small tips) are part of the culture for many services."),
        electrical: .init(plugTypes: ["C", "F"], voltage: "220V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Bottled water only.",
        commonScams: [
            "Aggressive vendors near Pyramids",
            "Inflated taxi fares — agree price first or use Uber/Careem",
            "'Free' camel rides that demand fees to dismount"
        ],
        phrases: [
            .init(english: "Hello / Peace be upon you", local: "السلام عليكم", pronunciation: "as-sa-laam a-lay-kum"),
            .init(english: "Thank you", local: "شكرا", pronunciation: "shoo-kran")
        ]
    )

    static let morocco = CountryEssentials(
        id: "MA", name: "Morocco", flagEmoji: "🇲🇦",
        emergency: .init(police: "19", ambulance: "15", fire: "15", general: "112", touristHotline: nil),
        tipping: .init(restaurantPercent: "10%", taxiPercent: "Round up", hotelPerDay: "MAD 20", note: nil),
        electrical: .init(plugTypes: ["C", "E"], voltage: "220V / 50Hz", needsAdapterForUS: true),
        waterSafe: false, waterNote: "Bottled water only.",
        commonScams: [
            "Marrakech: 'free' directions/help that demand money",
            "Inflated prices in souks — bargain hard",
            "Snake/monkey photos that demand high fees"
        ],
        phrases: [
            .init(english: "Hello", local: "السلام", pronunciation: "as-sa-laam"),
            .init(english: "Thank you", local: "شكرا", pronunciation: "shoo-kran")
        ]
    )
}
