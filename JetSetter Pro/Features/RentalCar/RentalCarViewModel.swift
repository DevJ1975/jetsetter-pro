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

    // MARK: - Init

    init() {
        // Investor demo mode: pre-populate Tokyo (NRT) results on cold open
        // so reviewers see 5 cars immediately without tapping Search.
        if MockDataService.isEnabled {
            let cal = Calendar.current
            let pickup  = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
            let dropoff = cal.date(byAdding: .day, value: 6, to: .now) ?? .now
            self.pickupLocation = "NRT"
            self.pickupDate = pickup
            self.dropoffDate = dropoff
            self.vehicles = RentalCarService.demoTokyoVehicles(pickupDate: pickup, dropoffDate: dropoff)
            self.hasSearched = true
            self.isLoading = false
        }
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
}
