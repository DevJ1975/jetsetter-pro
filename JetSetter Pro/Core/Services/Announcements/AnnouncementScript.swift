// File: Core/Services/Announcements/AnnouncementScript.swift
//
// Turns a flight event into the ordered list of recorded clips that say it out
// loud, the way a gate agent would: "Attention please. Your gate has changed.
// Delta flight fourteen twenty-three now departs from gate C twenty-two."
//
// Pure and `nonisolated` so every rule here is unit-tested without audio.
// `AnnouncementComposer` joins the clips into one sound file; this file only
// decides what to say.
//
// Two rules shaped it:
//   • Never say something wrong. If any part of a sentence can't be spoken
//     exactly (a three-letter ICAO code, a gate like "T1-G5", a five-digit
//     flight number), `clips(for:)` returns nil and the caller uses
//     `genericClips(for:)`, which says the kind of event and points to the
//     app. The notification text still carries the details.
//   • Times are spoken in the airport's zone, never the phone's. A traveler
//     who lands in Denver with the phone still on Eastern time must hear the
//     departure time printed on the board, not one two hours off.
//
// Clip names are resource basenames without an extension. The chimes are
// `.caf` files in Resources/Sounds and everything else is an `.m4a` in
// Resources/Announcements; `fileExtension(for:)` says which. Both folders land
// flat in the app bundle's root.

import Foundation

// MARK: - Announcement

/// A flight event the app can announce.
///
/// `airline` is the two-character IATA designator ("DL", "B6"). `flight` is
/// the flight number, either alone ("1423") or with its designator ("DL1423").
/// When `flight` carries its own designator, that one wins, because the number
/// belongs to that carrier (on a codeshare the caller should pass the
/// operating flight).
nonisolated enum Announcement: Hashable, Sendable {
    case gateChange(airline: String, flight: String, gate: String)
    case delay(airline: String, flight: String, newDeparture: Date, timeZone: TimeZone)
    case cancelled(airline: String, flight: String)
    case diverted(airline: String, flight: String)
    case boarding(airline: String, flight: String, gate: String)
    case boardingSoon(gate: String)
    case checkInOpen(airline: String, flight: String)
    case timeToLeave
    case connectionAtRisk
}

// MARK: - AnnouncementScript

nonisolated enum AnnouncementScript {

    // MARK: Chimes

    /// Two-tone cabin chime for alerts (Resources/Sounds/cabin_chime.caf).
    static let alertChime = "cabin_chime"
    /// Ascending boarding chime (Resources/Sounds/boarding.caf).
    static let boardingChime = "boarding"

    /// The chime that opens an announcement: the boarding chime for boarding
    /// events, so a traveler can tell "go to the gate" from "something changed"
    /// before a word is spoken.
    static func chime(for announcement: Announcement) -> String {
        switch announcement {
        case .boarding, .boardingSoon: return boardingChime
        default:                       return alertChime
        }
    }

    /// The chime's notification sound name, with extension ("cabin_chime.caf").
    static func chimeSoundName(for announcement: Announcement) -> String {
        let name = chime(for: announcement)
        return "\(name).\(fileExtension(for: name))"
    }

    // MARK: Phrases and words

    static let attention             = "phrase_attention"
    static let gateChanged           = "phrase_gate_changed"
    static let nowDepartsFromGate    = "phrase_now_departs_from_gate"
    static let isDelayed             = "phrase_is_delayed"
    static let newDepartureTimeIs    = "phrase_new_departure_time_is"
    static let hasBeenCancelled      = "phrase_has_been_cancelled"
    static let hasBeenDiverted       = "phrase_has_been_diverted"
    static let nowBoardingAtGate     = "phrase_now_boarding_at_gate"
    static let checkInOpenFor        = "phrase_checkin_open_for"
    static let timeToLeavePhrase     = "phrase_time_to_leave"
    static let connectionAtRiskPhrase = "phrase_connection_at_risk"
    static let boardingIn30AtGate    = "phrase_boarding_in_30_at_gate"
    static let checkApp              = "phrase_check_app"
    static let wordFlight            = "word_flight"
    static let wordAM                = "word_am"
    static let wordPM                = "word_pm"
    static let numHundred            = "num_hundred"
    static let numOh                 = "num_oh"

    /// Carriers with a recorded name clip (`airline_<code>`). Any other
    /// designator is spelled out.
    static let airlinesWithClips: Set<String> = [
        "DL", "UA", "AA", "WN", "B6", "AS", "NK", "F9", "HA", "G4",
        "SY", "AC", "WS", "BA", "VS", "LH", "AF", "KL", "EI", "EK",
        "QR", "TK", "SQ", "CX", "JL", "NH", "QF", "AM", "IB", "LX"
    ]

    /// Every voice clip a script can produce (174 files), without the chimes.
    static let voiceClipNames: [String] = {
        var names = [
            attention, gateChanged, nowDepartsFromGate, isDelayed, newDepartureTimeIs,
            hasBeenCancelled, hasBeenDiverted, nowBoardingAtGate, checkInOpenFor,
            timeToLeavePhrase, connectionAtRiskPhrase, boardingIn30AtGate, checkApp,
            wordFlight, wordAM, wordPM, numHundred, numOh
        ]
        names += airlinesWithClips.sorted().map { "airline_\($0.lowercased())" }
        names += "abcdefghijklmnopqrstuvwxyz".map { "letter_\($0)" }
        names += (0...99).map { "num_\($0)" }
        return names
    }()

    /// Every resource a script can reference: the voice clips plus both chimes.
    static var allClipNames: [String] { [alertChime, boardingChime] + voiceClipNames }

    /// "caf" for the chimes, "m4a" for the voice clips.
    static func fileExtension(for clip: String) -> String {
        clip == alertChime || clip == boardingChime ? "caf" : "m4a"
    }

    // MARK: - Scripts

    /// The full announcement, or nil when any part of it can't be said exactly.
    /// Always starts with the chime.
    static func clips(for announcement: Announcement) -> [String]? {
        let opening = chime(for: announcement)
        let body: [String]?
        switch announcement {
        case let .gateChange(airline, flight, gate):
            // "Your gate has changed. Delta flight 1423 now departs from gate C22."
            guard let flightClips = spokenFlight(airline: airline, flight: flight),
                  let gateClips = spokenGate(gate) else { return nil }
            body = [gateChanged] + flightClips + [nowDepartsFromGate] + gateClips

        case let .delay(airline, flight, newDeparture, timeZone):
            // "Delta flight 1423 is delayed. The new departure time is ten forty-five p.m."
            guard let flightClips = spokenFlight(airline: airline, flight: flight) else { return nil }
            body = flightClips + [isDelayed, newDepartureTimeIs] + spokenTime(newDeparture, in: timeZone)

        case let .cancelled(airline, flight):
            body = spokenFlight(airline: airline, flight: flight).map { $0 + [hasBeenCancelled] }

        case let .diverted(airline, flight):
            body = spokenFlight(airline: airline, flight: flight).map { $0 + [hasBeenDiverted] }

        case let .boarding(airline, flight, gate):
            // "Delta flight 1423 is now boarding at gate C22."
            guard let flightClips = spokenFlight(airline: airline, flight: flight),
                  let gateClips = spokenGate(gate) else { return nil }
            body = flightClips + [nowBoardingAtGate] + gateClips

        case let .boardingSoon(gate):
            body = spokenGate(gate).map { [boardingIn30AtGate] + $0 }

        case let .checkInOpen(airline, flight):
            // "Check-in is now open for Delta flight 1423."
            body = spokenFlight(airline: airline, flight: flight).map { [checkInOpenFor] + $0 }

        case .timeToLeave:
            body = [timeToLeavePhrase]

        case .connectionAtRisk:
            // There's nothing specific to add, so point to the app for the
            // onward options.
            body = [connectionAtRiskPhrase, checkApp]
        }
        guard let body else { return nil }
        return [opening, attention] + body
    }

    /// The fallback that every event can say: chime, "Attention please.", the
    /// event, "Please check the app for details."
    ///
    /// The recorded event phrases that end in "at gate" or "open for" can't
    /// stand alone without sounding broken ("…is now boarding at gate."), so
    /// boarding, boarding-soon and check-in say the chime and attention line
    /// only. The boarding chime alone already tells the traveler which kind of
    /// alert it is.
    static func genericClips(for announcement: Announcement) -> [String] {
        let event: [String]
        switch announcement {
        case .gateChange:                       event = [gateChanged]
        case .delay:                            event = [wordFlight, isDelayed]
        case .cancelled:                        event = [wordFlight, hasBeenCancelled]
        case .diverted:                         event = [wordFlight, hasBeenDiverted]
        case .timeToLeave:                      event = [timeToLeavePhrase]
        case .connectionAtRisk:                 event = [connectionAtRiskPhrase]
        case .boarding, .boardingSoon, .checkInOpen: event = []
        }
        return [chime(for: announcement), attention] + event + [checkApp]
    }

    /// The full script when it can be said exactly, otherwise the generic one.
    static func resolvedClips(for announcement: Announcement) -> [String] {
        clips(for: announcement) ?? genericClips(for: announcement)
    }

    // MARK: - Pauses

    /// Silence after the chime and after a complete sentence.
    static let sentencePause: TimeInterval = 0.25
    /// Silence between words inside a sentence.
    static let wordPause: TimeInterval = 0.06

    /// Clips that end a sentence, so the next clip starts after a longer breath.
    static let sentenceEndingClips: Set<String> = [
        alertChime, boardingChime, attention, gateChanged, isDelayed,
        hasBeenCancelled, hasBeenDiverted, timeToLeavePhrase, connectionAtRiskPhrase, checkApp
    ]

    /// Silence to insert after `clip`. Nothing after the last clip.
    static func pause(after clip: String, isLast: Bool) -> TimeInterval {
        if isLast { return 0 }
        return sentenceEndingClips.contains(clip) ? sentencePause : wordPause
    }

    // MARK: - Flight

    /// "Delta flight fourteen twenty-three", or "Flight U two forty-three
    /// twenty-one" for a carrier without a name clip. Nil when the designator
    /// isn't a two-character IATA code or the number isn't 1–9999.
    static func spokenFlight(airline: String, flight: String) -> [String]? {
        let compact = flight.uppercased().filter { !$0.isWhitespace }
        // Same designator rule as the rest of the app ("B6715" → "B6").
        let ownDesignator = TravelStore.airlineDesignator(from: compact)
        let numberText = String(compact.dropFirst(ownDesignator.count))
        let given = airline.uppercased().trimmingCharacters(in: .whitespaces)
        let designator = ownDesignator.isEmpty ? given : ownDesignator

        guard isIATADesignator(designator),
              let number = parseNumber(numberText, maxDigits: 4),
              let spokenNumber = spokenFlightNumber(number) else { return nil }

        if airlinesWithClips.contains(designator) {
            return ["airline_\(designator.lowercased())", wordFlight] + spokenNumber
        }
        guard let spelled = spell(designator) else { return nil }
        return [wordFlight] + spelled + spokenNumber
    }

    /// Flight numbers the way airlines say them:
    /// 7 → "seven", 805 → "eight oh five", 800 → "eight hundred",
    /// 1423 → "fourteen twenty-three", 1405 → "fourteen oh five",
    /// 1400 → "fourteen hundred". Nil outside 1–9999.
    static func spokenFlightNumber(_ number: Int) -> [String]? {
        guard (1...9999).contains(number) else { return nil }
        if number < 100 { return ["num_\(number)"] }
        // Hundreds digit (805) or leading pair (1423), then the last two digits.
        return ["num_\(number / 100)"] + spokenLastTwo(number % 100)
    }

    /// The trailing pair after a leading digit or pair: 0 → "hundred",
    /// 5 → "oh five", 23 → "twenty-three".
    private static func spokenLastTwo(_ pair: Int) -> [String] {
        switch pair {
        case 0:      return [numHundred]
        case 1...9:  return [numOh, "num_\(pair)"]
        default:     return ["num_\(pair)"]
        }
    }

    // MARK: - Gate

    /// Gates spoken run by run: "C22" → C, twenty-two; "B5" → B, five;
    /// "34" → thirty-four; "A101" → A, one oh one. Nil for empty input,
    /// punctuation ("T1-G5"), more than two runs of letters or digits, or a
    /// number over 999.
    static func spokenGate(_ gate: String) -> [String]? {
        let text = gate.uppercased().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 6,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }

        // Split into alternating letter and digit runs: "A101" → ["A", "101"].
        var runs: [String] = []
        for character in text {
            if let last = runs.last?.last, last.isNumber == character.isNumber {
                runs[runs.count - 1].append(character)
            } else {
                runs.append(String(character))
            }
        }
        // "C22", "22", "22B". Anything with more runs ("T1G5") is a
        // terminal-plus-gate code we can't be sure how to read.
        guard runs.count <= 2 else { return nil }

        var spoken: [String] = []
        for run in runs {
            if run.first?.isNumber == true {
                guard let value = parseNumber(run, maxDigits: 3), value <= 999 else { return nil }
                spoken += spokenGateNumber(value)
            } else {
                // Two letters at most ("AB12" is unusual but readable).
                guard run.count <= 2, let letters = spell(run) else { return nil }
                spoken += letters
            }
        }
        return spoken
    }

    /// 0–99 as one number, 100–999 like a flight number ("one oh one").
    private static func spokenGateNumber(_ value: Int) -> [String] {
        value < 100 ? ["num_\(value)"] : ["num_\(value / 100)"] + spokenLastTwo(value % 100)
    }

    // MARK: - Time

    /// A wall-clock time at the airport, 12-hour, as airlines say it:
    /// 22:45 → "ten forty-five p.m.", 09:05 → "nine oh five a.m.",
    /// 21:00 → "nine p.m.". `timeZone` must be the departure airport's zone.
    static func spokenTime(_ date: Date, in timeZone: TimeZone) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0

        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        var spoken = ["num_\(twelveHour)"]
        switch minute {
        case 0:     break
        case 1...9: spoken += [numOh, "num_\(minute)"]
        default:    spoken += ["num_\(minute)"]
        }
        spoken.append(hour < 12 ? wordAM : wordPM)
        return spoken
    }

    // MARK: - Helpers

    /// Two ASCII letters or digits with at least one letter ("DL", "B6", "9W").
    static func isIATADesignator(_ code: String) -> Bool {
        code.count == 2
            && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && code.contains(where: \.isLetter)
    }

    /// Letters and digits one by one: "B6" → B, six.
    private static func spell(_ text: String) -> [String]? {
        var spoken: [String] = []
        for character in text.lowercased() {
            guard character.isASCII else { return nil }
            if character.isLetter {
                spoken.append("letter_\(character)")
            } else if let digit = character.wholeNumberValue {
                spoken.append("num_\(digit)")
            } else {
                return nil
            }
        }
        return spoken
    }

    /// 1…`maxDigits` ASCII digits as an Int. Leading zeros are dropped
    /// ("0805" is flight 805).
    private static func parseNumber(_ text: String, maxDigits: Int) -> Int? {
        guard !text.isEmpty, text.count <= maxDigits,
              text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}
