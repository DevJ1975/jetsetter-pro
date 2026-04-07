// File: Features/RentalCar/RentalCarViewModel.swift

import SwiftUI
import Combine

@MainActor
final class RentalCarViewModel: ObservableObject {

    // MARK: - Search Parameters

    @Published var pickupLocation: String = ""
    @Published var dropoffLocation: String = ""
    @Published var isSameReturnLocation: Bool = true
    @Published var pickupDate: Date = .now
    @Published var dropoffDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @Published var selectedClass: VehicleClass? = nil
    @Published var selectedProviders: Set<RentalProvider> = Set(RentalProvider.allCases)

    // MARK: - Results State

    @Published var vehicles: [RentalVehicle] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasSearched: Bool = false

    // MARK: - Filter / Sort

    @Published var sortOption: SortOption = .priceAscending

    enum SortOption: String, CaseIterable {
        case priceAscending  = "Price: Low to High"
        case priceDescending = "Price: High to Low"
        case classAscending  = "Class: Economy First"
        case provider        = "Provider"
    }

    // MARK: - Derived (Cached) State
    // These are recomputed via Combine only when their inputs change,
    // not on every @Published property update in the ViewModel.

    @Published private(set) var sortedVehicles: [RentalVehicle] = []
    @Published private(set) var groupedByProvider: [(RentalProvider, [RentalVehicle])] = []
    @Published private(set) var availableClasses: [VehicleClass] = []

    private var sortCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        // Reactively recompute derived state only when vehicles, filter, or sort changes
        sortCancellable = $vehicles
            .combineLatest($selectedClass, $sortOption)
            .sink { [weak self] vehicles, selectedClass, sortOption in
                self?.recomputeDerivedState(
                    vehicles: vehicles,
                    selectedClass: selectedClass,
                    sortOption: sortOption
                )
            }
    }

    // MARK: - Derived State Computation

    private func recomputeDerivedState(
        vehicles: [RentalVehicle],
        selectedClass: VehicleClass?,
        sortOption: SortOption
    ) {
        // Filter by class if one is selected
        let base = selectedClass == nil ? vehicles : vehicles.filter { $0.vehicleClass == selectedClass }

        // Sort
        let sorted: [RentalVehicle]
        switch sortOption {
        case .priceAscending:  sorted = base.sorted { $0.dailyRate < $1.dailyRate }
        case .priceDescending: sorted = base.sorted { $0.dailyRate > $1.dailyRate }
        case .classAscending:  sorted = base.sorted { $0.vehicleClass.rawValue < $1.vehicleClass.rawValue }
        case .provider:        sorted = base.sorted { $0.provider.displayName < $1.provider.displayName }
        }
        sortedVehicles = sorted

        // Group by provider (preserving RentalProvider.allCases order)
        var dict: [RentalProvider: [RentalVehicle]] = [:]
        for v in sorted { dict[v.provider, default: []].append(v) }
        groupedByProvider = RentalProvider.allCases.compactMap { provider in
            guard let list = dict[provider], !list.isEmpty else { return nil }
            return (provider, list)
        }

        // Available class chips (based on full vehicle set, not filtered)
        availableClasses = Array(Set(vehicles.map(\.vehicleClass))).sorted { $0.rawValue < $1.rawValue }
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

    // MARK: - Booking (Deep Link)

    /// Attempts to open the provider's app via deep link; falls back to App Store.
    func book(vehicle: RentalVehicle) {
        let deepLink = vehicle.deepLinkURL()
        let fallback = vehicle.provider.appStoreURL

        if let deepLink, UIApplication.shared.canOpenURL(deepLink) {
            UIApplication.shared.open(deepLink)
        } else if let fallback {
            UIApplication.shared.open(fallback)
        }
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
