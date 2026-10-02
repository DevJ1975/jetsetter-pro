// File: JetSetter ProTests/WidgetSnapshotTests.swift
//
// Covers the payload the app hands its widgets through the App Group: that it
// round-trips, that older and damaged payloads still decode (a widget that
// can't read its data must show its empty state, not crash), that the
// original Next Trip widget can still read it, that it never carries a
// confirmation number, passenger name or barcode, and that an unchanged
// snapshot isn't treated as a change (each change spends a widget reload).
//
// Instants are mid-September 2026: Las Vegas is UTC-7 and Atlanta UTC-4.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct WidgetSnapshotTests {

    // MARK: - Fixtures

    private let lasVegas = "America/Los_Angeles"
    private let atlanta = "America/New_York"

    private func instant(day: Int, hour: Int, minute: Int, in zone: String) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)))
    }

    /// DL1423 LAS → ATL, departing 09:05 in Las Vegas on 14 September and
    /// landing 16:12 in Atlanta, on a three-day board-meeting trip.
    private func sampleSnapshot() throws -> WidgetSnapshot {
        let departure = try instant(day: 14, hour: 9, minute: 5, in: lasVegas)
        let arrival = try instant(day: 14, hour: 16, minute: 12, in: atlanta)
        let flight = WidgetSnapshot.FlightLeg(
            id: UUID(), flightNumber: "DL1423", airline: "Delta Air Lines",
            originCode: "LAS", originCity: "Las Vegas", destinationCode: "ATL", destinationCity: "Atlanta",
            departure: departure, arrival: arrival,
            originTimeZoneID: lasVegas, destinationTimeZoneID: atlanta,
            gate: "C22", terminal: "1", seat: "3A", walletPassID: UUID(),
            checkInOpensAt: departure.addingTimeInterval(-24 * 3_600),
            boardingEstimate: departure.addingTimeInterval(-30 * 60))
        let hotel = WidgetSnapshot.DayItem(
            id: UUID(), kind: .hotel, title: "The Ritz-Carlton, Atlanta",
            start: arrival.addingTimeInterval(90 * 60), timeZoneID: atlanta)
        let trip = WidgetSnapshot.TripSummary(
            id: UUID(), name: "Atlanta Board Meeting", destination: "Atlanta, GA",
            startDate: departure, endDate: departure.addingTimeInterval(3 * 86_400),
            destinationCode: "ATL", destinationTimeZoneID: atlanta,
            flights: [flight],
            items: [WidgetSnapshot.DayItem(id: flight.id, kind: .flight, title: "Delta DL1423",
                                           start: departure, timeZoneID: lasVegas), hotel],
            weather: WidgetSnapshot.Weather(temperatureFahrenheit: 74, symbolName: "sun.max.fill",
                                            condition: "Clear", isAppleWeather: true,
                                            observedAt: departure.addingTimeInterval(-3_600)))
        return WidgetSnapshot(
            schemaVersion: WidgetSnapshot.currentSchemaVersion,
            generatedAt: departure.addingTimeInterval(-4 * 3_600),
            homeTimeZoneID: lasVegas,
            trips: [trip],
            leaveBy: WidgetSnapshot.LeaveBy(flightID: flight.id, leaveAt: departure.addingTimeInterval(-2 * 3_600),
                                            usesLiveTraffic: true,
                                            computedAt: departure.addingTimeInterval(-3 * 3_600),
                                            expiresAt: departure.addingTimeInterval(3 * 3_600)))
    }

    // MARK: - Round trip and versions

    @Test func aSnapshotSurvivesAnEncodeDecodeRoundTrip() throws {
        let snapshot = try sampleSnapshot()
        let data = try #require(WidgetSnapshotStore.encode(snapshot))
        let decoded = try #require(WidgetSnapshotStore.decode(data))
        #expect(decoded == snapshot)
        #expect(decoded.schemaVersion == 2)
    }

    /// The original one-trip payload had four fields and no version key. A
    /// widget reading it after an app update must still find the trip.
    @Test func aVersionOnePayloadDecodesAsASingleTrip() throws {
        let json = """
        {"name":"Atlanta Board Meeting","destination":"Atlanta, GA",\
        "startDate":"2026-09-14T16:05:00Z","endDate":"2026-09-17T16:05:00Z"}
        """
        let snapshot = try #require(WidgetSnapshotStore.decode(Data(json.utf8)))
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.trips.count == 1)
        #expect(snapshot.trips.first?.name == "Atlanta Board Meeting")
        #expect(snapshot.trips.first?.destination == "Atlanta, GA")
        #expect(snapshot.trips.first?.startDate == Date(timeIntervalSince1970: 1_789_401_900))
        #expect(snapshot.trips.first?.flights.isEmpty == true)
        #expect(snapshot.leaveBy == nil)
        #expect(snapshot.homeTimeZoneID == nil)
    }

    /// One bad row, an unknown item kind or a mistyped optional must cost
    /// that row or that field, never the whole snapshot.
    @Test func aDamagedRowOrUnknownValueDoesNotSinkTheSnapshot() throws {
        let json = """
        {
          "schemaVersion": 3,
          "generatedAt": "2026-09-14T12:00:00Z",
          "fieldFromTheFuture": true,
          "leaveBy": {"flightID": "not a uuid"},
          "trips": [
            {
              "id": "6F1C2A40-0B6B-4C1E-9F0A-2D4B5C6D7E8F",
              "name": "Atlanta Board Meeting",
              "startDate": "2026-09-14T16:05:00Z",
              "endDate": "2026-09-17T16:05:00Z",
              "destinationTimeZoneID": 42,
              "flights": [
                {"id": "1A1C2A40-0B6B-4C1E-9F0A-2D4B5C6D7E8F", "departure": "2026-09-14T16:05:00Z",
                 "flightNumber": "DL1423", "gate": null, "seat": 3},
                {"id": "2A1C2A40-0B6B-4C1E-9F0A-2D4B5C6D7E8F", "flightNumber": "DL2244"}
              ],
              "items": [
                {"id": "3A1C2A40-0B6B-4C1E-9F0A-2D4B5C6D7E8F", "kind": "cruise",
                 "title": "Harbour cruise", "start": "2026-09-15T22:00:00Z"}
              ]
            },
            {"id": "not a uuid", "name": "Broken"}
          ]
        }
        """
        let snapshot = try #require(WidgetSnapshotStore.decode(Data(json.utf8)))
        #expect(snapshot.schemaVersion == 3)
        #expect(snapshot.leaveBy == nil)
        let trip = try #require(snapshot.trips.first)
        #expect(snapshot.trips.count == 1)
        #expect(trip.destination == "")
        #expect(trip.destinationTimeZoneID == nil)
        // The flight without a departure is dropped; the good one keeps its
        // known fields, and the mistyped seat becomes unknown.
        #expect(trip.flights.map(\.flightNumber) == ["DL1423"])
        #expect(trip.flights.first?.gate == nil)
        #expect(trip.flights.first?.seat == nil)
        #expect(trip.items.first?.kind == .other)
    }

    /// `NextTripWidget.swift` decodes exactly these four fields from the same
    /// key, and isn't changed by the version 2 work.
    @Test func versionTwoStillCarriesWhatTheOriginalNextTripWidgetReads() throws {
        let snapshot = try sampleSnapshot()
        let data = try #require(WidgetSnapshotStore.encode(snapshot))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(OriginalNextTripFields.self, from: data)
        let trip = try #require(snapshot.trips.first)
        #expect(legacy.name == trip.name)
        #expect(legacy.destination == trip.destination)
        #expect(legacy.startDate == trip.startDate)
        #expect(legacy.endDate == trip.endDate)
        #expect(WidgetSnapshotStore.snapshotKey == "jetsetter_next_trip_snapshot")
    }

    /// With no trip, the original widget must fail to decode and show its own
    /// "No upcoming trips", as it did when the key was removed.
    @Test func anEmptySnapshotGivesTheOriginalWidgetNothingToShow() throws {
        let data = try #require(WidgetSnapshotStore.encode(.empty(generatedAt: Date(timeIntervalSince1970: 1_789_401_900))))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect((try? decoder.decode(OriginalNextTripFields.self, from: data)) == nil)
    }

    // MARK: - Privacy

    /// The App Group container is readable by every process in the group, so
    /// a PNR, a passenger name or a boarding pass barcode must never reach it,
    /// even when the traveler typed the confirmation into a title or notes.
    @Test func theSnapshotNeverCarriesAConfirmationNumberNameOrBarcode() throws {
        let departure = try instant(day: 14, hour: 9, minute: 5, in: lasVegas)
        let arrival = try instant(day: 14, hour: 16, minute: 12, in: atlanta)
        let flight = ItineraryItem(
            title: "Delta DL1423 (Conf JX7QF2)",
            type: .flight,
            startDate: departure,
            endDate: arrival,
            location: "LAS → ATL",
            notes: "PNR JX7QF2 · Gate C22 · Passenger JANE DOE",
            confirmationNumber: "JX7QF2",
            bookingProvider: "Delta Air Lines",
            flightDetails: FlightBookingDetails(airline: "Delta Air Lines", flightNumber: "DL 1423",
                                                originCode: "LAS", destinationCode: "ATL", seat: "3A",
                                                cabinClass: "First", terminal: "1", gate: nil))
        let hotel = ItineraryItem(
            title: "Ritz-Carlton · Booking ref RC88421",
            type: .hotel,
            startDate: arrival.addingTimeInterval(90 * 60),
            confirmationNumber: "RC88421")
        let trip = Trip(name: "Atlanta Board Meeting", destination: "Atlanta, GA",
                        startDate: departure.addingTimeInterval(-3_600),
                        endDate: departure.addingTimeInterval(3 * 86_400),
                        items: [flight, hotel])
        let pass = WalletItem(
            itemType: .boardingPass, title: "DL1423 LAS–ATL", confirmationNumber: "JX7QF2", date: departure,
            rawData: ["flight_number": "DL1423", "seat_number": "3A", "passenger_name": "DOE/JANE",
                      "barcode_message": "M1DOE/JANE            EJX7QF2 LASATLDL 1423 257F003A0001 100"])

        let vegas = try #require(TimeZone(identifier: lasVegas))
        let snapshot = WidgetBridge.makeSnapshot(
            from: [trip],
            now: departure.addingTimeInterval(-3 * 3_600),
            inputs: WidgetBridge.Inputs(homeAirport: "LAS", walletItems: [pass], briefing: nil,
                                        previous: nil, deviceTimeZone: vegas))
        let json = String(decoding: try #require(WidgetSnapshotStore.encode(snapshot)), as: UTF8.self)

        #expect(!json.contains("JX7QF2"))
        #expect(!json.contains("RC88421"))
        #expect(!json.contains("M1DOE"))
        #expect(!json.contains("JANE"))
        #expect(!json.contains("Passenger"))

        // What the widgets do need is still there.
        let leg = try #require(snapshot.trips.first?.flights.first)
        #expect(leg.flightNumber == "DL1423")
        #expect(leg.gate == "C22")
        #expect(leg.seat == "3A")
        #expect(leg.walletPassID == pass.id)
        #expect(leg.originTimeZoneID == lasVegas)
        #expect(leg.destinationTimeZoneID == atlanta)
        #expect(snapshot.trips.first?.items.map(\.title) == ["Delta DL1423", "Ritz-Carlton"])
        #expect(snapshot.homeTimeZoneID == lasVegas)
    }

    @Test func labelledConfirmationNumbersAreScrubbedFromTitles() {
        #expect(WidgetBridge.scrubbed("Dinner — PNR: ABC123", removing: [], fallback: "x") == "Dinner")
        #expect(WidgetBridge.scrubbed("Confirmation number JX7QF2", removing: [], fallback: "Flight") == "Flight")
        // Words that merely start like a label survive.
        #expect(WidgetBridge.scrubbed("Conference keynote", removing: [], fallback: "x") == "Conference keynote")
        #expect(WidgetBridge.scrubbed("Confirmation dinner", removing: [], fallback: "x") == "Confirmation dinner")
    }

    // MARK: - Change detection

    /// Stored dates are whole seconds, so a trip date with a fractional second
    /// would never equal its own stored copy if compared as values, and every
    /// publish would spend one of the widgets' daily reloads.
    @Test func anUnchangedSnapshotIsNotAChangeEvenWithFractionalSeconds() throws {
        var snapshot = try sampleSnapshot()
        snapshot.trips[0].flights[0].departure += 0.4
        let stored = try #require(WidgetSnapshotStore.encode(snapshot))

        var republished = snapshot
        republished.generatedAt += 600
        #expect(!WidgetBridge.hasChanged(republished, comparedTo: stored))

        republished.trips[0].flights[0].gate = "C24"
        #expect(WidgetBridge.hasChanged(republished, comparedTo: stored))
        #expect(WidgetBridge.hasChanged(snapshot, comparedTo: nil))
    }

    // MARK: - Trip selection

    @Test func activeTripsComeFirstThenUpcomingOnesByStart() throws {
        let now = try instant(day: 14, hour: 12, minute: 0, in: lasVegas)
        let past = Trip(name: "Past", destination: "", startDate: now.addingTimeInterval(-9 * 86_400),
                        endDate: now.addingTimeInterval(-7 * 86_400))
        let later = Trip(name: "Later", destination: "", startDate: now.addingTimeInterval(9 * 86_400),
                         endDate: now.addingTimeInterval(10 * 86_400))
        let soon = Trip(name: "Soon", destination: "", startDate: now.addingTimeInterval(86_400),
                        endDate: now.addingTimeInterval(2 * 86_400))
        let active = Trip(name: "Active", destination: "", startDate: now.addingTimeInterval(-86_400),
                          endDate: now.addingTimeInterval(86_400))
        let order = WidgetBridge.upcomingTrips([later, past, soon, active], now: now).map(\.name)
        #expect(order == ["Active", "Soon", "Later"])
    }
}

/// The four fields `NextTripWidget.swift` decodes, mirrored here because its
/// type is private to the widget extension.
nonisolated private struct OriginalNextTripFields: Decodable {
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
}
