// File: Features/LuggageTracker/LuggageViewModel.swift

import Foundation
import SwiftUI
import UIKit

// MARK: - LuggageViewModel

/// Manages the user's registered bags, WorldTracer status lookups,
/// and Find My deep linking.
@MainActor
@Observable
final class LuggageViewModel {

    // MARK: - Published State

    var bags: [Bag] = []
    var isTracking: Bool = false
    var errorMessage: String? = nil
    var statusMessage: String? = nil

    // MARK: - UserDefaults Key

    private let storageKey = "jetsetter_bags"

    // MARK: - Init

    init() {
        loadBags()
    }

    // MARK: - Persistence

    func loadBags() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            // Must match the .iso8601 strategy MockDataService/DemoSeeder use to
            // write jetsetter_bags — a strategy mismatch threw here and silently
            // wiped the entire bag list on every launch.
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            bags = try decoder.decode([Bag].self, from: data)
        } catch {
            bags = []
        }
    }

    private func saveBags() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(bags)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            errorMessage = "Failed to save bag information."
        }
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

    // MARK: - WorldTracer Lookup

    /// Fetches the latest status for a bag from SITA WorldTracer and updates it locally.
    func trackBag(_ bag: Bag) async {
        guard let tagNumber = bag.bagTagNumber else {
            errorMessage = "This bag has no tag number. Add a bag tag number to track it via WorldTracer."
            return
        }

        isTracking = true
        errorMessage = nil
        statusMessage = nil

        defer { isTracking = false }

        do {
            let result = try await SITAWorldTracerService.shared.traceBag(tagNumber: tagNumber)

            // Update the matching bag with the latest status
            guard let index = bags.firstIndex(where: { $0.id == bag.id }) else { return }
            bags[index].status = result.mappedStatus
            bags[index].lastLocation = result.lastLocation
            bags[index].lastChecked = Date()

            // Update airline and flight from WorldTracer if not already set
            if bags[index].airline == nil { bags[index].airline = result.airline }
            if bags[index].flightNumber == nil { bags[index].flightNumber = result.flightNumber }

            saveBags()
            statusMessage = "Updated: \(bags[index].status.displayName)"

        } catch let error as WorldTracerError {
            errorMessage = error.errorDescription
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Could not reach WorldTracer. Please try again."
        }
    }

    /// Refreshes all bags that have a bag tag number.
    func refreshAllTrackableBags() async {
        let trackableBags = bags.filter { $0.bagTagNumber != nil }
        for bag in trackableBags {
            await trackBag(bag)
        }
    }

    // MARK: - Find My (in-app)

    /// In-app web target (§7.7). AirTag precise location is a Find My-only
    /// capability with no in-app API, so we present iCloud Find My on the web
    /// inside JetSetter Pro rather than launching the Find My app / App Store.
    var externalWebURL: URL?

    func openFindMy() {
        externalWebURL = URL(string: "https://www.icloud.com/find")
    }
}
