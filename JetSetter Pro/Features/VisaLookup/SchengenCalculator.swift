// File: Features/VisaLookup/SchengenCalculator.swift
//
// The Schengen 90-in-180 counter behind the Visa Requirements card. Lives
// outside the view so the counting and the place matching can be tested.
//
// Past defect: the counter only knew the 9 Schengen states that happen to be
// in the visa dataset, and it only counted a trip whose text named one of
// them. Sixty days in "Brussels, Belgium" counted as zero, and the card still
// said "90 of 90 days" with full confidence. It now knows all 29 members,
// resolves trips by country name, airport code or major city, and reports how
// many recent trips it couldn't place so the card can say the number may be
// high.
//
// The data is for US passport holders, as is everything in Visa Requirements.

import Foundation

enum SchengenCalculator {

    /// Days allowed in the whole area within any rolling window.
    static let allowanceDays = 90
    /// Length of the rolling window, in days.
    static let windowDays = 180

    /// The 29 Schengen members (ISO 3166-1 alpha-2), current as of 2025, when
    /// Bulgaria and Romania joined in full. Ireland and Cyprus are EU members
    /// but not in Schengen.
    static let memberCodes: Set<String> = [
        "AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE",
        "GR", "HU", "IS", "IT", "LV", "LI", "LT", "LU", "MT", "NL",
        "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH"
    ]

    static func isMember(_ isoCode: String) -> Bool {
        memberCodes.contains(isoCode.uppercased())
    }

    // MARK: - Placing a trip

    /// Where a trip's free-text destination puts it relative to Schengen.
    enum Placement: Equatable {
        /// Inside the area, with the member state's ISO code.
        case schengen(String)
        /// Somewhere we can name that isn't in the area.
        case outside
        /// Nothing in the text could be placed confidently.
        case unknown
    }

    /// Resolves a destination string, most specific evidence first.
    static func placement(for destination: String) -> Placement {
        let raw = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .unknown }
        let words = normalizedWords(raw)
        guard !words.isEmpty else { return .unknown }

        // 1. "City, ST" is a US address ("Paris, TX", "Athens, GA"), with one
        //    exception: DE and MT are also Germany and Malta, so "Munich, DE" and
        //    "Valletta, MT" stay in Europe when the city agrees with the code.
        if USStateCodes.isUSCityState(raw) {
            let parts = raw.split(separator: ",").map { normalizedWords(String($0)) }
            if let cityWords = parts.first,
               let stateWord = parts.last?.first?.uppercased(),
               let cityCode = matchRun(in: cityWords, table: cities),
               cityCode == stateWord {
                return .schengen(cityCode)
            }
            return .outside
        }

        // 2. A Schengen country named in full ("Brussels, Belgium").
        if let code = matchRun(in: words, table: countryNames) {
            return .schengen(code)
        }

        // 3. An airport code in capitals, last one first, since a route such as
        //    "JFK → CDG" ends at the destination.
        let airportTokens = raw
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count == 3 && $0 == $0.uppercased() }
        for token in airportTokens.reversed() {
            if let code = airports[token] { return .schengen(code) }
            if let country = TravelEssentialsData.find(query: token) {
                return isMember(country.id) ? .schengen(country.id) : .outside
            }
            if let zone = AirportCoordinates.timeZone(for: token)?.identifier,
               !zone.hasPrefix("Europe/"), !zone.hasPrefix("Atlantic/") {
                return .outside
            }
        }

        // 4. The app's two country matchers ("Toronto, Canada", "Tokyo, Japan").
        if let visa = VisaRequirements.find(query: raw) {
            return isMember(visa.destination) ? .schengen(visa.destination) : .outside
        }
        if let country = TravelEssentialsData.find(query: raw) {
            return isMember(country.id) ? .schengen(country.id) : .outside
        }

        // 5. Major cities, inside and outside the area.
        if let code = matchRun(in: words, table: cities) {
            return .schengen(code)
        }
        if matchRun(in: words, table: outsideCities) != nil {
            return .outside
        }
        return .unknown
    }

    // MARK: - Counting days

    struct Tally: Equatable {
        /// Distinct calendar days spent in the area inside the window.
        let daysUsed: Int
        /// `allowanceDays - daysUsed`, floored at zero.
        let daysRemaining: Int
        /// Trips overlapping the window whose destination couldn't be placed.
        /// Their days aren't counted, so `daysRemaining` may be too high.
        let unplacedTripCount: Int
    }

    /// Counts days in the area over the rolling window ending on `reference`.
    /// Days are collected as a set, so two overlapping trip records for the same
    /// stay don't count the same day twice. Future trips don't count yet.
    static func tally(trips: [Trip], asOf reference: Date = Date(),
                      calendar: Calendar = .current) -> Tally {
        let today = calendar.startOfDay(for: reference)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else {
            return Tally(daysUsed: 0, daysRemaining: allowanceDays, unplacedTripCount: 0)
        }

        var daysInArea = Set<Date>()
        var unplaced = 0
        for trip in trips {
            // Clamp the trip to the rolling window before looking at it.
            let overlapStart = max(calendar.startOfDay(for: trip.startDate), windowStart)
            let overlapEnd = min(calendar.startOfDay(for: trip.endDate), today)
            guard overlapStart <= overlapEnd else { continue }

            switch placement(for: trip.destination) {
            case .outside:
                continue
            case .unknown:
                unplaced += 1
            case .schengen:
                // Inclusive: the entry and exit days both count, as the rule says.
                var day = overlapStart
                while day <= overlapEnd {
                    daysInArea.insert(day)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
        }

        let used = daysInArea.count
        return Tally(daysUsed: used,
                     daysRemaining: max(0, allowanceDays - used),
                     unplacedTripCount: unplaced)
    }

    // MARK: - Matching helpers

    /// Lower-cased, accent-folded words ("Zürich" → "zurich", "Kraków" → "krakow").
    private static func normalizedWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// The value for the first table key that appears in `words` as a whole word
    /// or a contiguous run of words, so "Nice" never matches inside "Venice".
    private static func matchRun(in words: [String], table: [String: String]) -> String? {
        for (key, value) in table {
            let keyWords = key.split(separator: " ").map(String.init)
            guard !keyWords.isEmpty, keyWords.count <= words.count else { continue }
            for start in 0...(words.count - keyWords.count)
            where Array(words[start..<(start + keyWords.count)]) == keyWords {
                return value
            }
        }
        return nil
    }

    // MARK: - Data

    /// Schengen country names, including common alternatives and local names.
    private static let countryNames: [String: String] = [
        "austria": "AT", "osterreich": "AT",
        "belgium": "BE", "belgique": "BE", "belgie": "BE",
        "bulgaria": "BG",
        "croatia": "HR", "hrvatska": "HR",
        "czechia": "CZ", "czech republic": "CZ",
        "denmark": "DK", "danmark": "DK",
        "estonia": "EE",
        "finland": "FI", "suomi": "FI",
        "france": "FR",
        "germany": "DE", "deutschland": "DE",
        "greece": "GR",
        "hungary": "HU", "magyarorszag": "HU",
        "iceland": "IS",
        "italy": "IT", "italia": "IT",
        "latvia": "LV",
        "liechtenstein": "LI",
        "lithuania": "LT",
        "luxembourg": "LU",
        "malta": "MT",
        "netherlands": "NL", "holland": "NL", "nederland": "NL",
        "norway": "NO", "norge": "NO",
        "poland": "PL", "polska": "PL",
        "portugal": "PT",
        "romania": "RO",
        "slovakia": "SK",
        "slovenia": "SI",
        "spain": "ES", "espana": "ES",
        "sweden": "SE", "sverige": "SE",
        "switzerland": "CH", "schweiz": "CH", "suisse": "CH", "svizzera": "CH"
    ]

    /// Major airports in the area. Not exhaustive; an unknown code falls through
    /// to the other checks rather than being guessed.
    private static let airports: [String: String] = [
        "VIE": "AT", "SZG": "AT", "INN": "AT",
        "BRU": "BE", "CRL": "BE", "ANR": "BE",
        "SOF": "BG", "VAR": "BG",
        "ZAG": "HR", "SPU": "HR", "DBV": "HR",
        "PRG": "CZ",
        "CPH": "DK", "BLL": "DK",
        "TLL": "EE",
        "HEL": "FI",
        "CDG": "FR", "ORY": "FR", "NCE": "FR", "LYS": "FR", "MRS": "FR", "TLS": "FR", "BOD": "FR",
        "FRA": "DE", "MUC": "DE", "BER": "DE", "HAM": "DE", "DUS": "DE", "CGN": "DE", "STR": "DE",
        "ATH": "GR", "SKG": "GR", "JTR": "GR", "JMK": "GR", "HER": "GR",
        "BUD": "HU",
        "KEF": "IS",
        "FCO": "IT", "CIA": "IT", "MXP": "IT", "LIN": "IT", "BGY": "IT", "VCE": "IT", "FLR": "IT",
        "NAP": "IT", "BLQ": "IT", "PSA": "IT", "CTA": "IT", "PMO": "IT",
        "RIX": "LV",
        "VNO": "LT",
        "LUX": "LU",
        "MLA": "MT",
        "AMS": "NL", "EIN": "NL", "RTM": "NL",
        "OSL": "NO", "BGO": "NO",
        "WAW": "PL", "KRK": "PL", "GDN": "PL",
        "LIS": "PT", "OPO": "PT", "FAO": "PT", "FNC": "PT",
        "OTP": "RO",
        "BTS": "SK",
        "LJU": "SI",
        "MAD": "ES", "BCN": "ES", "AGP": "ES", "PMI": "ES", "SVQ": "ES", "VLC": "ES", "IBZ": "ES",
        "BIO": "ES", "ALC": "ES", "TFS": "ES", "LPA": "ES",
        "ARN": "SE", "GOT": "SE",
        "ZRH": "CH", "GVA": "CH", "BSL": "CH"
    ]

    /// Major cities in the area, accent-folded, with common local spellings.
    private static let cities: [String: String] = [
        "vienna": "AT", "wien": "AT", "salzburg": "AT", "innsbruck": "AT",
        "brussels": "BE", "bruxelles": "BE", "antwerp": "BE", "bruges": "BE", "ghent": "BE",
        "sofia": "BG",
        "zagreb": "HR", "dubrovnik": "HR",   // not "split": it is also an English word
        "prague": "CZ", "praha": "CZ",
        "copenhagen": "DK", "kobenhavn": "DK",
        "tallinn": "EE",
        "helsinki": "FI",
        "paris": "FR", "lyon": "FR", "nice": "FR", "marseille": "FR", "bordeaux": "FR",
        "toulouse": "FR", "strasbourg": "FR",
        "berlin": "DE", "munich": "DE", "munchen": "DE", "frankfurt": "DE", "hamburg": "DE",
        "cologne": "DE", "koln": "DE", "dusseldorf": "DE", "stuttgart": "DE",
        "athens": "GR", "thessaloniki": "GR", "santorini": "GR", "mykonos": "GR",
        "budapest": "HU",
        "reykjavik": "IS",
        "rome": "IT", "roma": "IT", "milan": "IT", "milano": "IT", "venice": "IT", "venezia": "IT",
        "florence": "IT", "firenze": "IT", "naples": "IT", "napoli": "IT", "bologna": "IT",
        "riga": "LV",
        "vilnius": "LT",
        "valletta": "MT",
        "amsterdam": "NL", "rotterdam": "NL", "the hague": "NL", "den haag": "NL",
        "oslo": "NO", "bergen": "NO",
        "warsaw": "PL", "warszawa": "PL", "krakow": "PL", "gdansk": "PL",
        "lisbon": "PT", "lisboa": "PT", "porto": "PT",
        "bucharest": "RO",
        "bratislava": "SK",
        "ljubljana": "SI",
        "madrid": "ES", "barcelona": "ES", "seville": "ES", "sevilla": "ES", "valencia": "ES",
        "malaga": "ES", "ibiza": "ES", "bilbao": "ES",
        "stockholm": "SE", "gothenburg": "SE",
        "zurich": "CH", "geneva": "CH", "geneve": "CH", "basel": "CH", "bern": "CH"
    ]

    /// Frequent business destinations outside the area, so an ordinary trip to
    /// one of them isn't reported as unplaced. The value is unused.
    private static let outsideCities: [String: String] = [
        "new york": "", "los angeles": "", "chicago": "", "houston": "", "dallas": "",
        "austin": "", "phoenix": "", "philadelphia": "", "san diego": "", "san francisco": "",
        "seattle": "", "denver": "", "boston": "", "atlanta": "", "miami": "", "orlando": "",
        "las vegas": "", "washington": "", "nashville": "", "charlotte": "", "detroit": "",
        "minneapolis": "", "honolulu": "", "new orleans": "", "salt lake city": "",
        "toronto": "", "vancouver": "", "montreal": "", "mexico city": "", "cancun": "",
        "london": "", "manchester": "", "edinburgh": "", "dublin": "",
        "nicosia": "", "limassol": "", "larnaca": "", "istanbul": "",
        "dubai": "", "abu dhabi": "", "doha": "", "tel aviv": "",
        "tokyo": "", "osaka": "", "seoul": "", "singapore": "", "hong kong": "",
        "shanghai": "", "beijing": "", "bangkok": "", "mumbai": "", "delhi": "",
        "sydney": "", "melbourne": "", "auckland": "",
        "sao paulo": "", "rio de janeiro": "", "buenos aires": "",
        "cape town": "", "johannesburg": "", "nairobi": "", "cairo": "", "marrakech": ""
    ]
}
