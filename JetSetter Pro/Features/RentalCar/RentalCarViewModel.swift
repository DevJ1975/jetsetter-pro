// File: Features/RentalCar/RentalCarViewModel.swift

import SwiftUI
import MapKit

@MainActor
@Observable
final class RentalCarViewModel {

    // MARK: - Search Parameters

    var pickupLocation: String = ""
    var pickupDate: Date = .now
    var dropoffDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    var selectedBrand: RentalBrand? = nil

    // MARK: - Results State

    var counters: [RentalCounter] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var hasSearched: Bool = false

    /// Transient explanation shown when the drop-off date is automatically
    /// pushed forward because it fell on or before the new pickup date.
    var dropoffAdjustmentNote: String? = nil

    // MARK: - Derived State

    /// Counters after the brand chip filter, nearest first.
    var filteredCounters: [RentalCounter] {
        guard let selectedBrand else { return counters }
        return counters.filter { $0.brand == selectedBrand }
    }

    /// Brands present in the result set, in filter-chip order.
    var availableBrands: [RentalBrand] {
        let present = Set(counters.map(\.brand))
        return RentalBrand.filterable.filter { present.contains($0) } + (present.contains(.other) ? [.other] : [])
    }

    var isOverFiltered: Bool { hasSearched && !counters.isEmpty && filteredCounters.isEmpty }

    // MARK: - Search

    func search() async {
        guard !pickupLocation.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a pickup location."
            return
        }
        guard dropoffDate > pickupDate else {
            errorMessage = "Drop-off date must be after pickup date."
            return
        }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        dropoffAdjustmentNote = nil
        counters = []
        selectedBrand = nil

        let params = RentalCarSearchParams(
            pickupLocation: pickupLocation,
            pickupDate: pickupDate,
            dropoffDate: dropoffDate
        )
        do {
            counters = try await RentalCarService.shared.searchCounters(params: params)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasSearched = true
    }

    func clearSearch() {
        counters = []
        errorMessage = nil
        hasSearched = false
        pickupLocation = ""
        selectedBrand = nil
    }

    // MARK: - Actions

    /// In-app web target for the brand's booking site (§7.7 — via `.inAppWeb`).
    var externalWebURL: URL?

    func book(_ counter: RentalCounter) {
        externalWebURL = counter.bookingURL
    }

    /// Opens Apple Maps with driving directions to the counter.
    func directions(to counter: RentalCounter) {
        counter.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Date Helpers

    var numberOfDays: Int {
        let diff = Calendar.current.dateComponents([.day], from: pickupDate, to: dropoffDate)
        return max(diff.day ?? 1, 1)
    }

    var dropoffMinimumDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: pickupDate) ?? pickupDate
    }

    func pickupDateChanged(to newPickup: Date) {
        guard dropoffDate <= newPickup else {
            dropoffAdjustmentNote = nil
            return
        }
        dropoffDate = Calendar.current.date(byAdding: .day, value: 1, to: newPickup) ?? newPickup
        dropoffAdjustmentNote = "Drop-off moved to keep it after pick-up."
    }
}
