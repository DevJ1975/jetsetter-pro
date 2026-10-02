// File: JetSetter ProTests/SpotlightAndCaptureTests.swift
//
// What goes into Spotlight and how it reads, plus the parts of screenshot
// capture that don't need the model: the Apple Intelligence status wording
// and the upright image handed to it. The Spotlight index and the model
// themselves can't run in a test host; their inputs can.

import Testing
import Foundation
import UIKit
import FoundationModels
@testable import JetSetter_Pro

struct SpotlightAndCaptureTests {

    private static let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    // MARK: - Spotlight selection

    @Test func endedTripsLeaveSpotlightAndCurrentOnesStay() {
        let past = Trip(name: "Spring offsite", destination: "Denver",
                        startDate: now.addingTimeInterval(-10 * Self.day), endDate: now.addingTimeInterval(-7 * Self.day))
        let active = Trip(name: "Board meeting", destination: "Atlanta",
                          startDate: now.addingTimeInterval(-Self.day), endDate: now.addingTimeInterval(Self.day))
        let upcoming = Trip(name: "Tokyo launch", destination: "Tokyo",
                            startDate: now.addingTimeInterval(20 * Self.day), endDate: now.addingTimeInterval(25 * Self.day))
        let picked = SpotlightSelection.trips(from: [upcoming, past, active], now: now)
        #expect(picked.map(\.name) == ["Board meeting", "Tokyo launch"])
    }

    @Test func aHotelStayUnderWayIsStillABookingButYesterdaysFlightIsNot() {
        let flown = ItineraryItem(title: "DL1423 LAS → ATL", type: .flight, startDate: now.addingTimeInterval(-Self.day))
        let stay = ItineraryItem(title: "The Ritz-Carlton, Atlanta", type: .hotel,
                                 startDate: now.addingTimeInterval(-Self.day), endDate: now.addingTimeInterval(2 * Self.day))
        let home = ItineraryItem(title: "DL1424 ATL → LAS", type: .flight, startDate: now.addingTimeInterval(2 * Self.day))
        let trip = Trip(name: "Board meeting", destination: "Atlanta",
                        startDate: now.addingTimeInterval(-Self.day), endDate: now.addingTimeInterval(2 * Self.day),
                        items: [home, flown, stay])
        let titles = SpotlightSelection.bookings(from: [trip], now: now).map(\.item.title)
        #expect(titles == ["The Ritz-Carlton, Atlanta", "DL1424 ATL → LAS"])
    }

    // MARK: - Booking subtitle

    /// A flight's time in Spotlight is the departure airport's wall clock, the
    /// same rule as the itinerary and Siri, so a traveler searching from
    /// Atlanta still sees the 9:05 Las Vegas departure.
    @Test func flightSubtitleReadsInTheDepartureAirportsZone() throws {
        let departure = try #require(ISO8601DateFormatter().date(from: "2026-09-14T16:05:00Z")) // 9:05 PDT
        let text = BookingEntity.summary(kind: .flight, start: departure, end: nil,
                                         originCode: "LAS", destinationCode: "ATL",
                                         locale: Locale(identifier: "en_US"))
        #expect(text.contains("9:05"))
        #expect(text.contains("LAS to ATL"))
        #expect(!text.contains("→"))
    }

    @Test func bookingEntityTakesStructuredFlightDetailsFirst() {
        let item = ItineraryItem(
            title: "Delta to Atlanta", type: .flight, startDate: now,
            confirmationNumber: "JX7QF2",
            flightDetails: FlightBookingDetails(airline: "Delta Air Lines", flightNumber: "DL1423",
                                                originCode: "LAS", destinationCode: "ATL")
        )
        let trip = Trip(name: "Board meeting", destination: "Atlanta", startDate: now, endDate: now.addingTimeInterval(Self.day))
        let entity = BookingEntity(item: item, trip: trip)
        #expect(entity.flightNumber == "DL1423")
        #expect(entity.originCode == "LAS")
        #expect(entity.destinationCode == "ATL")
        #expect(entity.provider == "Delta Air Lines")
    }

    // MARK: - Apple Intelligence status

    /// A phone still downloading the model must hear "getting ready", not the
    /// wording for a phone that will never run Apple Intelligence.
    @Test func aDownloadingModelSaysItIsGettingReady() {
        let status = AppleIntelligenceStatus.status(for: .unavailable(.modelNotReady))
        #expect(status == .gettingReady)
        #expect(BookingCapture.footnote(for: status).contains("getting ready"))
    }

    @Test func eachUnavailableReasonMapsToItsOwnStatus() {
        #expect(AppleIntelligenceStatus.status(for: .available) == .available)
        #expect(AppleIntelligenceStatus.status(for: .unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(AppleIntelligenceStatus.status(for: .unavailable(.appleIntelligenceNotEnabled)) == .notEnabled)
        #expect(BookingCapture.footnote(for: .notEnabled).contains("Settings"))
    }

    // MARK: - Image handed to the model

    private func image(width: Int, height: Int, orientation: UIImage.Orientation) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let cgImage = try #require(drawn.cgImage)
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    /// A portrait photo stored sideways with an EXIF flag must reach the model
    /// upright; `cgImage` alone drops the flag.
    @Test func sidewaysPhotosAreTurnedUprightForTheModel() throws {
        let sideways = try image(width: 40, height: 20, orientation: .right)
        let upright = try #require(VisionOCRService.uprightCGImage(sideways, maxEdge: 2_000))
        #expect(upright.width == 20)
        #expect(upright.height == 40)
    }

    @Test func largePhotosAreScaledDownToTheEdgeLimit() throws {
        let large = try image(width: 4_000, height: 2_000, orientation: .up)
        let scaled = try #require(VisionOCRService.uprightCGImage(large, maxEdge: 2_000))
        #expect(scaled.width == 2_000)
        #expect(scaled.height == 1_000)
    }
}
