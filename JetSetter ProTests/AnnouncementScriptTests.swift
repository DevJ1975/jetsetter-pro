// File: JetSetter ProTests/AnnouncementScriptTests.swift
//
// Spoken flight announcements: what the script says, and that every clip it
// can name ships in the app bundle. A missing clip doesn't crash; it silently
// downgrades the alert to the plain chime, which is why the bundle checks
// exist.
//
// Times are built from explicit IANA zones, so the results are the same on a
// CI runner in UTC and a phone in Atlanta.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct AnnouncementScriptTests {

    // MARK: - Fixtures

    /// The instant that reads `hour:minute` on 14 September 2026 in `zone`.
    private func instant(hour: Int, minute: Int, in zone: String) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: hour, minute: minute)))
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    // MARK: - Flight numbers

    @Test func fourDigitFlightNumbersAreSpokenAsTwoPairs() {
        #expect(AnnouncementScript.spokenFlightNumber(1423) == ["num_14", "num_23"])
        #expect(AnnouncementScript.spokenFlightNumber(1405) == ["num_14", "num_oh", "num_5"])
        #expect(AnnouncementScript.spokenFlightNumber(1400) == ["num_14", "num_hundred"])
        #expect(AnnouncementScript.spokenFlightNumber(2000) == ["num_20", "num_hundred"])
    }

    @Test func threeDigitFlightNumbersAreSpokenAsADigitThenAPair() {
        #expect(AnnouncementScript.spokenFlightNumber(837) == ["num_8", "num_37"])
        #expect(AnnouncementScript.spokenFlightNumber(805) == ["num_8", "num_oh", "num_5"])
        #expect(AnnouncementScript.spokenFlightNumber(800) == ["num_8", "num_hundred"])
    }

    @Test func oneAndTwoDigitFlightNumbersAreSpokenAsOneNumber() {
        #expect(AnnouncementScript.spokenFlightNumber(42) == ["num_42"])
        #expect(AnnouncementScript.spokenFlightNumber(7) == ["num_7"])
    }

    @Test func flightNumbersOutsideOneToNineThousandNineHundredNinetyNineCantBeSpoken() {
        #expect(AnnouncementScript.spokenFlightNumber(0) == nil)
        #expect(AnnouncementScript.spokenFlightNumber(10_000) == nil)
    }

    @Test func aFlightNumberWithItsOwnDesignatorIsSplitTheSameWayAsTheRestOfTheApp() {
        let separate = AnnouncementScript.spokenFlight(airline: "DL", flight: "1423")
        #expect(separate == ["airline_dl", "word_flight", "num_14", "num_23"])
        #expect(AnnouncementScript.spokenFlight(airline: "", flight: "DL1423") == separate)
        #expect(AnnouncementScript.spokenFlight(airline: "dl", flight: "DL 1423") == separate)
        // Leading zeros aren't spoken: flight 0805 is "eight oh five".
        #expect(AnnouncementScript.spokenFlight(airline: "UA", flight: "0805") == ["airline_ua", "word_flight", "num_8", "num_oh", "num_5"])
    }

    // MARK: - Airlines

    @Test func anAirlineWithoutAClipIsSpelledOutAfterTheWordFlight() {
        // easyJet has no name clip: "Flight U two forty-three twenty-one".
        #expect(AnnouncementScript.spokenFlight(airline: "U2", flight: "4321")
                == ["word_flight", "letter_u", "num_2", "num_43", "num_21"])
        #expect(AnnouncementScript.clips(for: .cancelled(airline: "U2", flight: "4321"))
                == ["cabin_chime", "phrase_attention", "word_flight", "letter_u", "num_2",
                    "num_43", "num_21", "phrase_has_been_cancelled"])
    }

    @Test func aDesignatorThatIsntTwoCharactersFallsBackToTheGenericAnnouncement() {
        // A three-letter ICAO code would be read out letter by letter, which is
        // not how anyone says the airline, so the script declines.
        #expect(AnnouncementScript.spokenFlight(airline: "DAL", flight: "1423") == nil)
        #expect(AnnouncementScript.spokenFlight(airline: "Delta", flight: "1423") == nil)
        #expect(AnnouncementScript.spokenFlight(airline: "DL", flight: "") == nil)
        #expect(AnnouncementScript.spokenFlight(airline: "DL", flight: "14235") == nil)
        #expect(AnnouncementScript.clips(for: .cancelled(airline: "DAL", flight: "1423")) == nil)
    }

    // MARK: - Gates

    @Test func gatesAreSpokenRunByRun() {
        #expect(AnnouncementScript.spokenGate("C22") == ["letter_c", "num_22"])
        #expect(AnnouncementScript.spokenGate("B5") == ["letter_b", "num_5"])
        #expect(AnnouncementScript.spokenGate("34") == ["num_34"])
        #expect(AnnouncementScript.spokenGate("A101") == ["letter_a", "num_1", "num_oh", "num_1"])
        #expect(AnnouncementScript.spokenGate(" c22 ") == ["letter_c", "num_22"])
    }

    @Test func gatesThatCantBeReadWithConfidenceReturnNil() {
        #expect(AnnouncementScript.spokenGate("T1-G5") == nil)
        #expect(AnnouncementScript.spokenGate("T1G5") == nil)
        #expect(AnnouncementScript.spokenGate("") == nil)
        #expect(AnnouncementScript.spokenGate("   ") == nil)
        #expect(AnnouncementScript.spokenGate("A1000") == nil)
        #expect(AnnouncementScript.spokenGate("—") == nil)
    }

    @Test func anUnreadableGateTurnsAGateChangeIntoTheGenericAnnouncement() {
        let change = Announcement.gateChange(airline: "DL", flight: "1423", gate: "T1-G5")
        #expect(AnnouncementScript.clips(for: change) == nil)
        #expect(AnnouncementScript.resolvedClips(for: change) == AnnouncementScript.genericClips(for: change))
    }

    // MARK: - Times

    @Test func timesAreSpokenInTwelveHourFormInTheAirportZone() throws {
        let la = try zone("America/Los_Angeles")
        let tenFortyFivePM = try instant(hour: 22, minute: 45, in: "America/Los_Angeles")
        let nineOhFiveAM = try instant(hour: 9, minute: 5, in: "America/Los_Angeles")
        let ninePM = try instant(hour: 21, minute: 0, in: "America/Los_Angeles")
        #expect(AnnouncementScript.spokenTime(tenFortyFivePM, in: la) == ["num_10", "num_45", "word_pm"])
        #expect(AnnouncementScript.spokenTime(nineOhFiveAM, in: la) == ["num_9", "num_oh", "num_5", "word_am"])
        #expect(AnnouncementScript.spokenTime(ninePM, in: la) == ["num_9", "word_pm"])
    }

    @Test func midnightAndNoonAreTwelve() throws {
        let la = try zone("America/Los_Angeles")
        let halfPastMidnight = try instant(hour: 0, minute: 30, in: "America/Los_Angeles")
        let noon = try instant(hour: 12, minute: 0, in: "America/Los_Angeles")
        #expect(AnnouncementScript.spokenTime(halfPastMidnight, in: la) == ["num_12", "num_30", "word_am"])
        #expect(AnnouncementScript.spokenTime(noon, in: la) == ["num_12", "word_pm"])
    }

    @Test func theSameInstantIsSpokenAsTheDepartureAirportsWallClockNotThePhones() throws {
        // 22:45 in Las Vegas is 01:45 the next morning in Atlanta. A traveler
        // whose phone is still on Eastern time must hear the Las Vegas time.
        let departure = try instant(hour: 22, minute: 45, in: "America/Los_Angeles")
        let lasVegas = try zone("America/Los_Angeles")
        let atlanta = try zone("America/New_York")
        let delay = Announcement.delay(airline: "DL", flight: "1423", newDeparture: departure, timeZone: lasVegas)
        #expect(AnnouncementScript.clips(for: delay)
                == ["cabin_chime", "phrase_attention", "airline_dl", "word_flight", "num_14", "num_23",
                    "phrase_is_delayed", "phrase_new_departure_time_is", "num_10", "num_45", "word_pm"])
        #expect(AnnouncementScript.spokenTime(departure, in: atlanta) == ["num_1", "num_45", "word_am"])
    }

    // MARK: - Full scripts

    @Test func aGateChangeReadsLikeAGateAgent() {
        #expect(AnnouncementScript.clips(for: .gateChange(airline: "DL", flight: "1423", gate: "C22"))
                == ["cabin_chime", "phrase_attention", "phrase_gate_changed", "airline_dl", "word_flight",
                    "num_14", "num_23", "phrase_now_departs_from_gate", "letter_c", "num_22"])
    }

    @Test func boardingEventsOpenWithTheBoardingChime() {
        #expect(AnnouncementScript.clips(for: .boarding(airline: "B6", flight: "715", gate: "B5"))
                == ["boarding", "phrase_attention", "airline_b6", "word_flight", "num_7", "num_15",
                    "phrase_now_boarding_at_gate", "letter_b", "num_5"])
        #expect(AnnouncementScript.clips(for: .boardingSoon(gate: "34"))
                == ["boarding", "phrase_attention", "phrase_boarding_in_30_at_gate", "num_34"])
    }

    @Test func eventsWithoutDetailsAlwaysHaveAFullScript() {
        #expect(AnnouncementScript.clips(for: .timeToLeave)
                == ["cabin_chime", "phrase_attention", "phrase_time_to_leave"])
        #expect(AnnouncementScript.clips(for: .connectionAtRisk)
                == ["cabin_chime", "phrase_attention", "phrase_connection_at_risk", "phrase_check_app"])
        #expect(AnnouncementScript.clips(for: .checkInOpen(airline: "AA", flight: "100"))
                == ["cabin_chime", "phrase_attention", "phrase_checkin_open_for", "airline_aa", "word_flight",
                    "num_1", "num_hundred"])
        #expect(AnnouncementScript.clips(for: .diverted(airline: "UA", flight: "837"))
                == ["cabin_chime", "phrase_attention", "airline_ua", "word_flight", "num_8", "num_37",
                    "phrase_has_been_diverted"])
    }

    // MARK: - Generic fallbacks

    @Test func everyCaseHasAGenericFallbackThatOpensWithItsChimeAndEndsByPointingToTheApp() throws {
        let departure = try instant(hour: 9, minute: 5, in: "America/Los_Angeles")
        let lasVegas = try zone("America/Los_Angeles")
        let expected: [(Announcement, [String])] = [
            (.gateChange(airline: "DL", flight: "1423", gate: "C22"),
             ["cabin_chime", "phrase_attention", "phrase_gate_changed", "phrase_check_app"]),
            (.delay(airline: "DL", flight: "1423", newDeparture: departure, timeZone: lasVegas),
             ["cabin_chime", "phrase_attention", "word_flight", "phrase_is_delayed", "phrase_check_app"]),
            (.cancelled(airline: "DL", flight: "1423"),
             ["cabin_chime", "phrase_attention", "word_flight", "phrase_has_been_cancelled", "phrase_check_app"]),
            (.diverted(airline: "DL", flight: "1423"),
             ["cabin_chime", "phrase_attention", "word_flight", "phrase_has_been_diverted", "phrase_check_app"]),
            (.boarding(airline: "DL", flight: "1423", gate: "C22"),
             ["boarding", "phrase_attention", "phrase_check_app"]),
            (.boardingSoon(gate: "C22"),
             ["boarding", "phrase_attention", "phrase_check_app"]),
            (.checkInOpen(airline: "DL", flight: "1423"),
             ["cabin_chime", "phrase_attention", "phrase_check_app"]),
            (.timeToLeave,
             ["cabin_chime", "phrase_attention", "phrase_time_to_leave", "phrase_check_app"]),
            (.connectionAtRisk,
             ["cabin_chime", "phrase_attention", "phrase_connection_at_risk", "phrase_check_app"])
        ]
        for (announcement, clips) in expected {
            #expect(AnnouncementScript.genericClips(for: announcement) == clips)
        }
    }

    // MARK: - Pauses

    @Test func longPausesFollowTheChimeAndWholeSentencesAndShortOnesFollowWords() {
        #expect(AnnouncementScript.pause(after: "cabin_chime", isLast: false) == AnnouncementScript.sentencePause)
        #expect(AnnouncementScript.pause(after: "phrase_gate_changed", isLast: false) == AnnouncementScript.sentencePause)
        #expect(AnnouncementScript.pause(after: "airline_dl", isLast: false) == AnnouncementScript.wordPause)
        #expect(AnnouncementScript.pause(after: "num_22", isLast: true) == 0)
    }

    // MARK: - Bundle

    @Test func everyVoiceClipAScriptCanNameShipsInTheAppBundle() {
        #expect(AnnouncementScript.voiceClipNames.count == 174)
        for name in AnnouncementScript.voiceClipNames {
            let url = Bundle.main.url(forResource: name, withExtension: AnnouncementScript.fileExtension(for: name))
            #expect(url != nil, "Missing \(name).m4a in the app bundle")
        }
    }

    @Test func bothChimesShipInTheAppBundle() {
        for name in [AnnouncementScript.alertChime, AnnouncementScript.boardingChime] {
            let url = Bundle.main.url(forResource: name, withExtension: AnnouncementScript.fileExtension(for: name))
            #expect(url != nil, "Missing \(name).caf in the app bundle")
        }
    }

    @Test func scriptsOnlyNameClipsFromTheVocabulary() throws {
        let vocabulary = Set(AnnouncementScript.allClipNames)
        let la = try zone("America/Los_Angeles")

        for number in 1...9_999 {
            let spoken = try #require(AnnouncementScript.spokenFlightNumber(number))
            #expect(spoken.allSatisfy(vocabulary.contains), "Flight \(number) uses a missing clip")
        }
        for hour in 0..<24 {
            for minute in 0..<60 {
                let date = try instant(hour: hour, minute: minute, in: "America/Los_Angeles")
                let spoken = AnnouncementScript.spokenTime(date, in: la)
                #expect(spoken.allSatisfy(vocabulary.contains), "\(hour):\(minute) uses a missing clip")
            }
        }
        let designators = AnnouncementScript.airlinesWithClips.sorted() + ["U2", "9W", "ZZ"]
        for designator in designators {
            let spoken = try #require(AnnouncementScript.spokenFlight(airline: designator, flight: "1405"))
            #expect(spoken.allSatisfy(vocabulary.contains), "\(designator) uses a missing clip")
        }
        for gate in ["A1", "Z999", "B22", "0", "22B", "AB12"] {
            let spoken = try #require(AnnouncementScript.spokenGate(gate))
            #expect(spoken.allSatisfy(vocabulary.contains), "Gate \(gate) uses a missing clip")
        }
    }

    // MARK: - Composer naming

    @Test func theComposedFileNameIsTheSameForTheSameClipList() {
        let clips = AnnouncementScript.resolvedClips(for: .gateChange(airline: "DL", flight: "1423", gate: "C22"))
        let first = AnnouncementComposer.fileName(for: clips, salt: "v1-42")
        #expect(first == AnnouncementComposer.fileName(for: clips, salt: "v1-42"))
        #expect(first.range(of: #"^ann_[0-9a-f]{16}\.caf$"#, options: .regularExpression) != nil)
    }

    @Test func aDifferentClipListOrBuildGetsADifferentFile() {
        let c22 = AnnouncementScript.resolvedClips(for: .gateChange(airline: "DL", flight: "1423", gate: "C22"))
        let c23 = AnnouncementScript.resolvedClips(for: .gateChange(airline: "DL", flight: "1423", gate: "C23"))
        #expect(AnnouncementComposer.fileName(for: c22, salt: "v1-42") != AnnouncementComposer.fileName(for: c23, salt: "v1-42"))
        #expect(AnnouncementComposer.fileName(for: c22, salt: "v1-42") != AnnouncementComposer.fileName(for: c22, salt: "v1-43"))
    }

    // MARK: - Setting

    @Test func theVoiceSettingDefaultsToChimeAndVoiceAndRoundTrips() throws {
        let suite = "AnnouncementScriptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AnnouncementSettings.voiceAnnouncements(in: defaults) == .chimeAndVoice)

        AnnouncementSettings.setVoiceAnnouncements(.chimeOnly, in: defaults)
        #expect(AnnouncementSettings.voiceAnnouncements(in: defaults) == .chimeOnly)

        // A value this build doesn't know never silences alerts.
        defaults.set("whisper", forKey: AnnouncementSettings.voiceAnnouncementsKey)
        #expect(AnnouncementSettings.voiceAnnouncements(in: defaults) == .chimeAndVoice)
    }
}
