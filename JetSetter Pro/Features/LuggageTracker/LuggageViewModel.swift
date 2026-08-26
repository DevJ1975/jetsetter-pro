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

    // MARK: - Init

    init() {
        loadBags()
    }

    // MARK: - Persistence

    // Bags persist through `BagStore` (SwiftData-backed), the single coding path
    // shared with the demo seeders. This removes the old iso8601-vs-default date
    // strategy mismatch that silently wiped the bag list on launch.
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

            // Update the matching bag with the latest authoritative status.
            guard let index = bags.firstIndex(where: { $0.id == bag.id }) else { return }
            applyTrace(result, to: index)

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
    ///
    /// Runs the WorldTracer lookups concurrently under a single tracking flag so
    /// the spinner toggles once for the whole batch (instead of flickering per
    /// bag), and reports an aggregate result rather than only the last bag's.
    func refreshAllTrackableBags() async {
        let trackableBags = bags.filter { $0.bagTagNumber != nil }
        guard !trackableBags.isEmpty else { return }

        isTracking = true
        errorMessage = nil
        statusMessage = nil
        defer { isTracking = false }

        // Fetch all traces concurrently; collect results keyed by bag id so we can
        // apply them on the main actor without interleaving mutations.
        let traces = await withTaskGroup(of: (UUID, Result<WorldTracerBagResponse, Error>).self) { group in
            for bag in trackableBags {
                guard let tagNumber = bag.bagTagNumber else { continue }
                group.addTask {
                    do {
                        let result = try await SITAWorldTracerService.shared.traceBag(tagNumber: tagNumber)
                        return (bag.id, .success(result))
                    } catch {
                        return (bag.id, .failure(error))
                    }
                }
            }
            var collected: [(UUID, Result<WorldTracerBagResponse, Error>)] = []
            for await item in group { collected.append(item) }
            return collected
        }

        var updatedCount = 0
        var notFoundCount = 0
        var otherFailureCount = 0
        for (bagID, result) in traces {
            switch result {
            case .success(let response):
                if let index = bags.firstIndex(where: { $0.id == bagID }) {
                    applyTrace(response, to: index)
                    updatedCount += 1
                }
            case .failure(let error):
                if case WorldTracerError.bagNotFound = error {
                    notFoundCount += 1
                } else {
                    otherFailureCount += 1
                }
            }
        }

        if updatedCount > 0 { saveBags() }

        var parts: [String] = []
        if updatedCount > 0 { parts.append("Updated \(updatedCount) bag\(updatedCount == 1 ? "" : "s")") }
        if notFoundCount > 0 { parts.append("\(notFoundCount) not found") }
        if otherFailureCount > 0 { parts.append("\(otherFailureCount) failed") }

        let summary = parts.joined(separator: ", ")
        if updatedCount > 0 {
            statusMessage = summary
        } else if !summary.isEmpty {
            errorMessage = summary
        }
    }

    /// Applies an authoritative WorldTracer trace onto the bag at `index`.
    ///
    /// Trusts WorldTracer's airline/flight/status/location as the source of
    /// truth on refresh (so a rerouted bag reflects its new flight), but only
    /// overwrites `lastLocation` when the response actually provides one — a nil
    /// location must not blank out a previously known position.
    private func applyTrace(_ result: WorldTracerBagResponse, to index: Int) {
        bags[index].status = result.mappedStatus
        if let location = result.lastLocation { bags[index].lastLocation = location }
        bags[index].lastChecked = Date()
        if let airline = result.airline { bags[index].airline = airline }
        if let flightNumber = result.flightNumber { bags[index].flightNumber = flightNumber }
    }

    /// Marks a bag as unable to be located and immediately re-checks WorldTracer
    /// so the user gets the freshest available status after reporting it missing.
    func reportMissing(_ bag: Bag) async {
        guard let index = bags.firstIndex(where: { $0.id == bag.id }) else { return }
        bags[index].status = .missing
        bags[index].lastChecked = Date()
        saveBags()
        statusMessage = "Marked \"\(bags[index].nickname)\" as missing. Re-checking WorldTracer…"

        // If the bag is trackable, pull the latest authoritative status.
        if bags[index].bagTagNumber != nil {
            await trackBag(bags[index])
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
