// File: JetSetter ProTests/VendorHandoffTests.swift
//
// When the app asks "Did you book? Save your reservation". The rule is "never
// nagging", so these pin when it must stay quiet: a bounce, a second ask in the
// same shopping session, a map or ride link, and after the traveler opts out.
// Also the backend hand-off queries and button wording.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct VendorHandoffTests {

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    // MARK: - Policy

    @Test func asksAfterARealVisitToABookingSite() throws {
        #expect(VendorHandoffPolicy.shouldPrompt(
            url: try url("https://www.delta.com/flights"), openedFor: 90, sinceLastPrompt: nil, enabled: true))
        #expect(VendorHandoffPolicy.shouldPrompt(
            url: try url("https://www.kayak.com/flights/LAS-ATL/2026-11-02"), openedFor: 45, sinceLastPrompt: 3_600, enabled: true))
    }

    @Test func staysQuietAfterABounce() throws {
        let link = try url("https://www.hertz.com/")
        #expect(!VendorHandoffPolicy.shouldPrompt(url: link, openedFor: 3, sinceLastPrompt: nil, enabled: true))
        #expect(VendorHandoffPolicy.shouldPrompt(
            url: link, openedFor: VendorHandoffPolicy.minimumDwell, sinceLastPrompt: nil, enabled: true))
    }

    /// Comparing three hotel sites is one shopping session, not three bookings.
    @Test func staysQuietWithinTheCooldownOfTheLastAsk() throws {
        let link = try url("https://www.marriott.com/")
        #expect(!VendorHandoffPolicy.shouldPrompt(url: link, openedFor: 120, sinceLastPrompt: 60, enabled: true))
        #expect(!VendorHandoffPolicy.shouldPrompt(
            url: link, openedFor: 120, sinceLastPrompt: VendorHandoffPolicy.cooldown - 1, enabled: true))
        #expect(VendorHandoffPolicy.shouldPrompt(
            url: link, openedFor: 120, sinceLastPrompt: VendorHandoffPolicy.cooldown, enabled: true))
    }

    @Test func neverAsksOnceTheTravelerTurnedItOff() throws {
        #expect(!VendorHandoffPolicy.shouldPrompt(
            url: try url("https://www.delta.com/"), openedFor: 300, sinceLastPrompt: nil, enabled: false))
    }

    @Test func linksThatCannotBeAReservationNeverPrompt() throws {
        for text in ["https://maps.apple.com/?q=Hilton", "https://m.uber.com/ul/?action=setPickup",
                     "https://www.lyft.com/ride", "https://weather.com/", "uber://?action=setPickup",
                     "mailto:support@jetsetterpro.app", "tel:+14155550123"] {
            #expect(!VendorHandoffPolicy.isBookingLink(try url(text)), "\(text) should not prompt")
        }
        #expect(VendorHandoffPolicy.isBookingLink(try url("https://www.delta.com/")))
        #expect(VendorHandoffPolicy.isBookingLink(try url("https://secure.hilton.com/book")))
    }

    @Test func theVendorIsNamedByItsHostWithoutWww() throws {
        #expect(VendorHandoffPolicy.displayHost(try url("https://www.delta.com/flights?x=1")) == "delta.com")
        #expect(VendorHandoffPolicy.displayHost(try url("https://m.kayak.com/")) == "m.kayak.com")
        #expect(VendorHandoffPolicy.displayHost(try url("mailto:a@b.com")) == nil)
    }

    @Test func eachHandoffKindOpensTheRightBookingForm() {
        #expect(VendorHandoffKind.flight.itemType == .flight)
        #expect(VendorHandoffKind.hotel.itemType == .hotel)
        #expect(VendorHandoffKind.car.itemType == .transport)
        #expect(VendorHandoffKind.car.noun == "rental car")
    }

    // MARK: - Backend hand-off queries

    private func values(_ items: [URLQueryItem]?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (items ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func flightQueryUsesTheDocumentedNames() throws {
        let depart = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        let back = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))

        let round = values(HandoffQuery.flights(origin: " las ", destination: "atl", depart: depart, return: back, adults: 2))
        #expect(round == ["origin": "LAS", "destination": "ATL", "depart": "2026-11-02", "return": "2026-11-05", "adults": "2"])

        let oneWay = values(HandoffQuery.flights(origin: "LAS", destination: "ATL", depart: depart, return: nil, adults: 0))
        #expect(oneWay["return"] == nil)
        #expect(oneWay["adults"] == "1")
    }

    @Test func incompleteSearchesAskForNothing() throws {
        let now = Date()
        #expect(HandoffQuery.flights(origin: "LAS", destination: "LAS", depart: now, return: nil, adults: 1) == nil)
        #expect(HandoffQuery.flights(origin: "LA", destination: "ATL", depart: now, return: nil, adults: 1) == nil)
        #expect(HandoffQuery.flights(origin: "", destination: "", depart: now, return: nil, adults: 1) == nil)
        #expect(HandoffQuery.hotels(destination: "  ", checkIn: now, checkOut: now, guests: 1) == nil)
        #expect(HandoffQuery.cars(pickup: "", pickupDate: now, dropoffDate: now) == nil)
    }

    @Test func hotelAndCarQueriesUseTheDocumentedNames() throws {
        let inDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        let outDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))

        #expect(values(HandoffQuery.hotels(destination: "Atlanta", checkIn: inDate, checkOut: outDate, guests: 2))
                == ["destination": "Atlanta", "check_in": "2026-11-02", "check_out": "2026-11-05", "guests": "2"])
        #expect(values(HandoffQuery.cars(pickup: "ATL", pickupDate: inDate, dropoffDate: outDate))
                == ["pickup": "ATL", "pickup_date": "2026-11-02", "dropoff_date": "2026-11-05"])
    }

    @Test func providerButtonsReadNaturally() {
        func title(_ kind: String?, _ name: String) -> String {
            HandoffQuery.buttonTitle(for: BackendHandoffProvider(id: "x", name: name, url: "https://example.com", kind: kind))
        }
        #expect(title("airline", "Delta Air Lines") == "Book on Delta Air Lines")
        #expect(title("hotel", "Marriott") == "Book on Marriott")
        #expect(title("car_rental", "Hertz") == "Reserve with Hertz")
        #expect(title("agency", "Kayak") == "Compare on Kayak")
        #expect(title(nil, "Kayak") == "Compare on Kayak")
    }
}
