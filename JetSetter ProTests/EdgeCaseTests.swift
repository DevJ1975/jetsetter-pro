// File: JetSetter ProTests/EdgeCaseTests.swift
// Edge-case coverage for the Apple-first rebuild: URL builders, brand and
// airline resolution, receipt parsing, the departure board, memory dedup,
// encrypted vault photos, and the read-only Siri intents. Pure logic only —
// no network, no on-device model.

import Testing
import Foundation
import CoreLocation
import UIKit
@testable import JetSetter_Pro

@Suite(.serialized)
struct EdgeCaseTests {

    // MARK: - Airline links

    @Test func airlineLinksResolveNamesCodesAndFlightNumbers() {
        #expect(AirlineWebLinks.homepage(for: "Delta Air Lines")?.host == "www.delta.com")
        #expect(AirlineWebLinks.homepage(for: "DL")?.host == "www.delta.com")
        #expect(AirlineWebLinks.homepage(for: "dl2244")?.host == "www.delta.com")
        #expect(AirlineWebLinks.homepage(for: "B6 1234")?.host == "www.jetblue.com")
        #expect(AirlineWebLinks.homepage(for: "KLM Royal Dutch Airlines")?.host == "www.klm.com")
        #expect(AirlineWebLinks.homepage(for: "") == nil)
        #expect(AirlineWebLinks.homepage(for: nil) == nil)
        #expect(AirlineWebLinks.homepage(for: "ZZ999") == nil)
    }

    // MARK: - Rental brands

    @Test func rentalBrandDetectionHandlesRealCounterNames() {
        #expect(RentalBrand.detect(from: "Hertz Car Rental") == .hertz)
        #expect(RentalBrand.detect(from: "Enterprise Rent-A-Car") == .enterprise)
        #expect(RentalBrand.detect(from: "SIXT rent a car") == .sixt)
        #expect(RentalBrand.detect(from: "Joe's Auto Repair") == .other)
        #expect(RentalBrand.other.websiteURL == nil)
        for brand in RentalBrand.allCases where brand != .other {
            #expect(brand.websiteURL != nil)
        }
    }

    @Test func rentalSearchParamsNeverReportZeroDays() {
        var params = RentalCarSearchParams()
        params.pickupDate = Date(timeIntervalSince1970: 1_800_000_000)
        params.dropoffDate = params.pickupDate
        #expect(params.numberOfDays == 1)
        params.dropoffDate = params.pickupDate.addingTimeInterval(86_400 * 2 + 3_600)
        #expect(params.numberOfDays == 2)
    }

    // MARK: - Ride and hotel URLs

    @Test func rideURLsEncodeCoordinatesAndAddresses() {
        let pickup = CLLocation(latitude: 41.9742, longitude: -87.9073)
        let dropoff = CLLocation(latitude: 41.8781, longitude: -87.6298)
        let address = "233 S Wacker Dr & Adams, Chicago"
        for provider in RideProvider.allCases {
            let url = provider.rideURL(pickup: pickup, dropoff: dropoff, dropoffAddress: address)
            #expect(url != nil)
            #expect(url?.scheme == "https")
            #expect(url?.absoluteString.contains("41.8781") == true)
        }
        // No pickup fix yet → Uber falls back to "my_location" and still builds.
        #expect(RideProvider.uber.rideURL(pickup: nil, dropoff: dropoff, dropoffAddress: address)?.absoluteString.contains("my_location") == true)
    }

    @Test func hotelHandoffURLHandlesSpacesAndRejectsEmptyDestination() {
        var params = HotelSearchParams()
        params.destination = "New York, NY"
        params.checkInDate = Date(timeIntervalSince1970: 1_800_000_000)
        params.checkOutDate = params.checkInDate.addingTimeInterval(86_400 * 3)
        params.adults = 2
        let url = HotelBookingProvider.kayak.deepLinkURL(for: params)
        #expect(url?.host == "www.kayak.com")
        #expect(url?.path.hasSuffix("/2adults") == true)
        #expect(url?.absoluteString.contains(" ") == false)
        params.destination = "   "
        #expect(HotelBookingProvider.kayak.deepLinkURL(for: params) == nil)
        #expect(params.numberOfNights == 3)
    }

    // MARK: - Receipt parsing (regex tier)

    @Test func receiptParserPrefersGrandTotalOverSubtotal() {
        let text = """
        BLUE BOTTLE COFFEE
        66 Mint St
        Latte            5.25
        Croissant        4.50
        SUBTOTAL         9.75
        TAX              0.88
        TOTAL           10.63
        Thank you!
        """
        let result = VisionOCRService.shared.parseReceiptText(text)
        #expect(result.extractedAmount == 10.63)
        #expect(result.extractedMerchant == "BLUE BOTTLE COFFEE")
    }

    @Test func receiptParserHandlesEuropeanDecimalsAndNoKeywords() {
        let text = """
        Café Central
        Wiener Melange   4,90
        Sachertorte      6,50
        Summe           11,40
        """
        let result = VisionOCRService.shared.parseReceiptText(text)
        #expect(result.extractedAmount == 11.40)
        #expect(result.extractedMerchant == "Café Central")
    }

    @Test func receiptParserSurvivesEmptyAndNumericOnlyText() {
        let empty = VisionOCRService.shared.parseReceiptText("")
        #expect(empty.extractedAmount == nil)
        #expect(empty.extractedMerchant == nil)
        let digits = VisionOCRService.shared.parseReceiptText("1234567890\n0044 22 11")
        #expect(digits.extractedMerchant == nil)
    }

    // MARK: - Departure board

    @Test func departureBoardIsLabeledSampleWithoutFlightsAndRealWithOne() {
        let tripsKey = TravelStore.tripsKey
        let saved = UserDefaults.standard.data(forKey: tripsKey)
        let savedTrips = TravelStore.loadTrips()
        defer {
            TravelStore.saveTrips(savedTrips)
            UserDefaults.standard.set(saved, forKey: tripsKey)
        }

        TravelStore.saveTrips([])
        let empty = FlightBoardData.generate()
        #expect(empty.isSample)
        #expect(!empty.rows.isEmpty)
        #expect(empty.rows.allSatisfy { !$0.isUserFlight })

        let departure = Date().addingTimeInterval(3 * 3_600)
        var trip = Trip(name: "Board test", destination: "Tokyo", startDate: Date(), endDate: departure.addingTimeInterval(86_400))
        trip.items = [ItineraryItem(title: "Flight — DL2244 BOS → ORD", type: .flight, startDate: departure, location: "BOS → ORD", notes: "Gate B27")]
        TravelStore.saveTrips([trip])
        let mine = FlightBoardData.generate()
        #expect(!mine.isSample)
        #expect(mine.rows.count == 1)
        #expect(mine.rows.first?.flightNumber == "DL2244")
        #expect(mine.rows.first?.gate == "B27")
        #expect(mine.rows.first?.destinationIATA == "ORD")
    }

    // MARK: - Traveler memory

    @Test func travelerMemoryDedupesPhrasingsAndSupersedesSingleValuedCategories() {
        let memory = TravelerMemory.shared
        let snapshot = memory.preferences
        defer {
            memory.forgetEverything()
            for pref in snapshot { memory.remember(category: pref.category, value: pref.value) }
        }
        memory.forgetEverything()

        memory.remember(category: .seating, value: "Aisle seat")
        memory.remember(category: .seating, value: "aisle  seats.")
        #expect(memory.recall(category: .seating).count == 1)
        #expect(memory.recall(category: .seating).first?.confidence ?? 0 > 0.7)

        memory.remember(category: .dietary, value: "vegetarian")
        memory.remember(category: .dietary, value: "vegan")
        let dietary = memory.recall(category: .dietary)
        #expect(dietary.first?.value == "vegan")
        #expect(dietary.count == 2)
        #expect(memory.summaryForPrompt().contains("vegan"))

        memory.remember(category: .general, value: "   ")
        #expect(memory.recall(category: .general).first?.value == "")
    }

    // MARK: - Vault photos

    @Test func vaultPhotoRoundTripsEncryptedAndDeletes() throws {
        // The Keychain-backed key is unavailable to an unsigned simulator test
        // host (errSecMissingEntitlement); skip rather than fail there.
        guard (try? VaultCrypto.encrypt(Data([1, 2, 3]))) != nil else { return }
        let id = UUID()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try #require(image.pngData())
        let name = try DocumentVaultStore.savePhoto(data, for: id)
        #expect(name.hasSuffix(".enc"))
        let loaded = DocumentVaultStore.loadPhoto(named: name)
        #expect(loaded == data)
        #expect(DocumentVaultStore.loadPhoto(named: "missing.enc") == nil)
        #expect(DocumentVaultStore.loadPhoto(named: nil) == nil)
        DocumentVaultStore.deletePhoto(named: name)
        #expect(DocumentVaultStore.loadPhoto(named: name) == nil)
    }

    // MARK: - Local data store

    @Test func localDataStoreRoundTripsWalletAndPackingLists() async {
        let store = LocalDataService.shared
        let originalWallet = await store.fetchWalletItems()
        defer {
            Task {
                let stale = await store.fetchWalletItems()
                for item in stale where !originalWallet.contains(where: { $0.id == item.id }) {
                    await store.deleteWalletItem(id: item.id)
                }
            }
        }
        let item = WalletItem(itemType: .travelInsurance, title: "Test policy", date: Date(), rawData: ["policy_number": "X-1"])
        await store.upsertWalletItem(item)
        var items = await store.fetchWalletItems()
        #expect(items.contains { $0.id == item.id && $0.rawData["policy_number"] == "X-1" })
        await store.upsertWalletItem(item)          // idempotent
        items = await store.fetchWalletItems()
        #expect(items.filter { $0.id == item.id }.count == 1)
        await store.deleteWalletItem(id: item.id)
        items = await store.fetchWalletItems()
        #expect(!items.contains { $0.id == item.id })

        let tripID = UUID()
        let list = PackingListResult(id: UUID(), tripId: tripID, items: [SmartPackingItem(name: "Socks", category: .clothing, quantity: 5)], generatedAt: Date())
        await store.upsertPackingList(list)
        let fetched = await store.fetchPackingList(tripId: tripID)
        #expect(fetched?.items.first?.name == "Socks")
        #expect(await store.fetchPackingList(tripId: UUID()) == nil)
    }

    // MARK: - Boarding pass → wallet

    @Test func scannedPassBecomesWalletItemWithWalletKeys() {
        var pass = BoardingPass()
        pass.flightNumber = "DL 2244"
        pass.airlineCode = "DL"
        pass.originCode = "BOS"
        pass.destinationCode = "ORD"
        pass.seat = "12C"
        pass.pnr = "ABC123"
        let item = CheckInFlowView.walletItem(from: pass, fallbackFlightNumber: "XX000", fallbackDate: Date())
        #expect(item.itemType == .boardingPass)
        #expect(item.rawData["flight_number"] == "DL2244")
        #expect(item.rawData["seat_number"] == "12C")
        #expect(item.rawData["departure_airport"] == "BOS")
        #expect(item.confirmationNumber == "ABC123")
        #expect(item.title.contains("BOS → ORD"))

        let bare = CheckInFlowView.walletItem(from: BoardingPass(), fallbackFlightNumber: "UA55", fallbackDate: Date())
        #expect(bare.rawData["flight_number"] == "UA55")
        #expect(bare.rawData["seat_number"] == "—")
    }

    // MARK: - Siri enums and read-only intents

    @Test func appEnumsHaveDisplayRepresentationsForEveryCase() {
        for c in ExpenseCategoryChoice.allCases { #expect(ExpenseCategoryChoice.caseDisplayRepresentations[c] != nil) }
        for c in PreferenceCategoryChoice.allCases { #expect(PreferenceCategoryChoice.caseDisplayRepresentations[c] != nil) }
        for c in AppScreen.allCases { #expect(AppScreen.caseDisplayRepresentations[c] != nil) }
        for c in LovedOnesMilestone.allCases { #expect(LovedOnesMilestone.caseDisplayRepresentations[c] != nil) }
    }

    @Test func readOnlyIntentsAnswerWithoutData() async throws {
        let tripsKey = TravelStore.tripsKey
        let savedTrips = TravelStore.loadTrips()
        defer { TravelStore.saveTrips(savedTrips) }
        TravelStore.saveTrips([])
        _ = tripsKey

        // The dialog text isn't exposed on the opaque result; what matters is
        // that each read-only intent completes without throwing when the app
        // holds no data at all (Siri would otherwise report an error).
        _ = try await NextFlightIntent().perform()
        _ = try await NextTripIntent().perform()
        _ = try await DepartureBriefingIntent().perform()
        _ = try await BagStatusIntent().perform()
        _ = try await TravelPersonaIntent().perform()
    }

    @Test func appShortcutsStayWithinSiriLimits() {
        let shortcuts = JetSetterAppShortcuts.appShortcuts
        #expect(shortcuts.count <= 10)
    }

    // MARK: - Suggestions with no data

    @Test func suggestionsAreEmptyWithoutTripsOrLoyalty() {
        let savedTrips = TravelStore.loadTrips()
        let loyaltyKey = "jetsetter_loyalty_accounts"
        let savedLoyalty = UserDefaults.standard.data(forKey: loyaltyKey)
        defer {
            TravelStore.saveTrips(savedTrips)
            UserDefaults.standard.set(savedLoyalty, forKey: loyaltyKey)
        }
        TravelStore.saveTrips([])
        UserDefaults.standard.removeObject(forKey: loyaltyKey)
        #expect(ProactiveSuggestions.shared.evaluateAll().isEmpty)
    }
}
