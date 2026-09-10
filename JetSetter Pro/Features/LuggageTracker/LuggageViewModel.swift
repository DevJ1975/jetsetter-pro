// File: Features/LuggageTracker/LuggageViewModel.swift

import Foundation
import SwiftUI

// MARK: - LuggageViewModel

/// Manages the user's registered bags. Bag status comes from three honest
/// sources: what the airline's own site says (opened in-app), an AirTag in
/// Find My, and what the traveler records themselves. SITA WorldTracer's API
/// needs a carrier partner contract, so the app no longer pretends to call it.
@MainActor
@Observable
final class LuggageViewModel {

    // MARK: - Published State

    var bags: [Bag] = []
    var errorMessage: String? = nil
    var statusMessage: String? = nil

    // MARK: - Init

    init() {
        loadBags()
    }

    // MARK: - Persistence

    // Bags persist through `BagStore` (SwiftData-backed).
    func loadBags() {
        bags = BagStore.load()
    }

    private func saveBags() {
        BagStore.save(bags)
    }

    // MARK: - Bag CRUD

    func addBag(_ bag: Bag) {
        bags.append(bag)
        saveBags()
    }

    func deleteBag(at offsets: IndexSet) {
        bags.remove(atOffsets: offsets)
        saveBags()
    }

    // MARK: - Status (recorded by the traveler)

    /// Records a new status for the bag and appends a timeline event so the
    /// detail screen shows when and where it changed.
    func updateStatus(_ bag: Bag, to status: BagStatus, location: String? = nil) {
        guard let index = bags.firstIndex(where: { $0.id == bag.id }) else { return }
        bags[index].status = status
        bags[index].lastChecked = Date()
        if let location, !location.isEmpty { bags[index].lastLocation = location }
        if let scanType = Self.scanType(for: status) {
            bags[index].scanHistory.append(
                BagScanEvent(timestamp: Date(), location: bags[index].lastLocation ?? "", scanType: scanType)
            )
        }
        saveBags()
        statusMessage = "\(bags[index].nickname): \(status.displayName)"
    }

    /// Marks a bag as unable to be located and opens the airline's site so the
    /// traveler can file the delayed-bag report with the carrier.
    func reportMissing(_ bag: Bag) {
        guard let index = bags.firstIndex(where: { $0.id == bag.id }) else { return }
        bags[index].status = .missing
        bags[index].lastChecked = Date()
        saveBags()
        statusMessage = "Marked \"\(bags[index].nickname)\" as missing."
        openAirlineSite(for: bags[index])
    }

    private static func scanType(for status: BagStatus) -> BagScanEvent.ScanType? {
        switch status {
        case .checkedIn:  return .checkIn
        case .onBelt:     return .onBelt
        case .loading:    return .loaderTransfer
        case .onAircraft: return .securedInCargo
        case .arrived:    return .landed
        case .atCarousel, .delivered: return .claimed
        default:          return nil
        }
    }

    // MARK: - Airline + Find My (in-app web, §7.7)

    var externalWebURL: URL?
    var externalWebTitle: String = "Find My"

    /// True when the bag's airline (or flight number) maps to a known carrier site.
    func airlineURL(for bag: Bag) -> URL? {
        AirlineWebLinks.homepage(for: bag.airline) ?? AirlineWebLinks.homepage(for: bag.flightNumber)
    }

    /// Opens the airline's site in-app so the traveler can check bag status
    /// with their tag number, or file a delayed-bag report.
    func openAirlineSite(for bag: Bag) {
        guard let url = airlineURL(for: bag) else {
            errorMessage = "Add the airline or flight number to this bag to open the carrier's baggage page."
            return
        }
        externalWebTitle = bag.airline ?? "Airline"
        externalWebURL = url
    }

    /// AirTag precise location is a Find My-only capability with no in-app API,
    /// so we present iCloud Find My on the web inside JetSetter Pro.
    func openFindMy() {
        externalWebTitle = "Find My"
        externalWebURL = URL(string: "https://www.icloud.com/find")
    }
}
