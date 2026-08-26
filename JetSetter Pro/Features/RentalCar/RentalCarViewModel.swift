// File: Features/RentalCar/RentalCarViewModel.swift

import SwiftUI

@MainActor
@Observable
final class RentalCarViewModel {

    // MARK: - Search Parameters

    var pickupLocation: String = ""
    var dropoffLocation: String = ""
    var isSameReturnLocation: Bool = true
    var pickupDate: Date = .now
    var dropoffDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    var selectedClass: VehicleClass? = nil
    var selectedProviders: Set<RentalProvider> = Set(RentalProvider.allCases)

    // MARK: - Results State

    var vehicles: [RentalVehicle] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var hasSearched: Bool = false

    /// Transient explanation shown when the drop-off date is automatically
    /// pushed forward because it fell on or before the new pickup date. Cleared
    /// by the caller (or the next successful search) so it never lingers.
    var dropoffAdjustmentNote: String? = nil

    // MARK: - Filter / Sort

    var sortOption: SortOption = .priceAscending

    enum SortOption: String, CaseIterable {
        case priceAscending  = "Price: Low to High"
        case priceDescending = "Price: High to Low"
        case classAscending  = "Class: Economy First"
        case provider        = "Provider"
    }

    // MARK: - Derived State
    // Computed from the search inputs. Observation only invalidates views that
    // read these when one of the underlying stored properties actually changes.

    var sortedVehicles: [RentalVehicle] {
        // Filter by class if one is selected
        let classFiltered = selectedClass == nil ? vehicles : vehicles.filter { $0.vehicleClass == selectedClass }

        // Filter by selected provider chips
        let base = classFiltered.filter { selectedProviders.contains($0.provider) }

        // Sort
        switch sortOption {
        case .priceAscending:  return base.sorted { $0.dailyRate < $1.dailyRate }
        case .priceDescending: return base.sorted { $0.dailyRate > $1.dailyRate }
        case .classAscending:  return base.sorted { $0.vehicleClass.rawValue < $1.vehicleClass.rawValue }
        case .provider:        return base.sorted { $0.provider.displayName < $1.provider.displayName }
        }
    }

    var groupedByProvider: [(RentalProvider, [RentalVehicle])] {
        // Group by provider (preserving RentalProvider.allCases order)
        var dict: [RentalProvider: [RentalVehicle]] = [:]
        for v in sortedVehicles { dict[v.provider, default: []].append(v) }
        return RentalProvider.allCases.compactMap { provider in
            guard let list = dict[provider], !list.isEmpty else { return nil }
            return (provider, list)
        }
    }

    var availableClasses: [VehicleClass] {
        // Available class chips (based on full vehicle set, not filtered)
        Array(Set(vehicles.map(\.vehicleClass))).sorted { $0.rawValue < $1.rawValue }
    }

    /// True when a completed search returned vehicles, but the active class /
    /// provider filters exclude every one of them. The view uses this to show a
    /// non-destructive "No cars match your filters" state (with `resetFilters()`)
    /// instead of the generic empty state whose only exit is `clearSearch()`.
    var isOverFiltered: Bool {
        hasSearched && !vehicles.isEmpty && sortedVehicles.isEmpty
    }

    /// True when the user has narrowed results below the full set — i.e. a
    /// specific class is selected or at least one provider chip is off. Drives
    /// the active-filter badge so users can see why fewer cars are showing and
    /// know where to widen the filters.
    var hasActiveFilters: Bool {
        selectedClass != nil || selectedProviders.count < RentalProvider.allCases.count
    }

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
        vehicles = []

        let params = RentalCarSearchParams(
            pickupLocation: pickupLocation,
            dropoffLocation: isSameReturnLocation ? pickupLocation : dropoffLocation,
            pickupDate: pickupDate,
            dropoffDate: dropoffDate,
            vehicleClass: nil,
            providers: Array(selectedProviders)
        )

        do {
            let results = try await RentalCarService.shared.searchVehicles(params: params)
            vehicles = results
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        hasSearched = true
    }

    func clearSearch() {
        vehicles = []
        errorMessage = nil
        hasSearched = false
        pickupLocation = ""
        dropoffLocation = ""
        isSameReturnLocation = true
        selectedClass = nil
    }

    /// Non-destructive recovery from an over-filtered result set: clears the
    /// class filter and re-enables every provider chip while preserving the
    /// pickup location, dates, and fetched `vehicles`. Lets a user who
    /// over-filtered get back to results without redoing the whole search.
    func resetFilters() {
        selectedClass = nil
        selectedProviders = Set(RentalProvider.allCases)
    }

    // MARK: - Booking (in-app)

    /// In-app web target for the provider booking site (§7.7 — via `.inAppWeb`).
    var externalWebURL: URL?

    /// Presents the provider's booking site inside JetSetter Pro rather than
    /// handing off to the provider app / App Store (§7.7 in-app-only rule).
    func book(vehicle: RentalVehicle) {
        externalWebURL = vehicle.provider.websiteURL
    }

    // MARK: - Date Helpers

    var numberOfDays: Int {
        let diff = Calendar.current.dateComponents([.day], from: pickupDate, to: dropoffDate)
        return max(diff.day ?? 1, 1)
    }

    var dropoffMinimumDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: pickupDate) ?? pickupDate
    }

    /// Called when the pickup date changes. If the current drop-off would no
    /// longer be after pickup, pushes it forward by a day and records a short,
    /// visible note explaining the change instead of silently mutating it.
    func pickupDateChanged(to newPickup: Date) {
        guard dropoffDate <= newPickup else {
            dropoffAdjustmentNote = nil
            return
        }
        dropoffDate = Calendar.current.date(byAdding: .day, value: 1, to: newPickup) ?? newPickup
        dropoffAdjustmentNote = "Drop-off moved to keep it after pick-up."
    }
}
