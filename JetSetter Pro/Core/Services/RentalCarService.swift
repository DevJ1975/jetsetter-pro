// File: Core/Services/RentalCarService.swift

import Foundation

// MARK: - Rental Car Service Errors

enum RentalCarError: LocalizedError {
    case invalidLocation
    case invalidDateRange
    case noVehiclesAvailable
    case apiError(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidLocation:
            return "Please enter a valid pickup location."
        case .invalidDateRange:
            return "Drop-off date must be after pickup date."
        case .noVehiclesAvailable:
            return "No vehicles available for the selected dates and location."
        case .apiError(let msg):
            return msg
        case .decodingFailed:
            return "Could not parse rental car results. Please try again."
        }
    }
}

// MARK: - Rental Car Service

/// Unified rental car search service that fans out to Enterprise, Hertz, and National,
/// normalises each provider's response into [RentalVehicle], then merges and sorts.
actor RentalCarService {

    static let shared = RentalCarService()
    private init() {}

    // MARK: - Public API

    /// Searches all requested providers in parallel and returns merged, sorted results.
    func searchVehicles(params: RentalCarSearchParams) async throws -> [RentalVehicle] {
        guard !params.pickupLocation.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw RentalCarError.invalidLocation
        }
        guard params.dropoffDate > params.pickupDate else {
            throw RentalCarError.invalidDateRange
        }

        // Fan out to each requested provider concurrently
        var allVehicles: [RentalVehicle] = []
        try await withThrowingTaskGroup(of: [RentalVehicle].self) { group in
            for provider in params.providers {
                group.addTask {
                    try await self.fetchVehicles(provider: provider, params: params)
                }
            }
            for try await vehicles in group {
                allVehicles.append(contentsOf: vehicles)
            }
        }

        guard !allVehicles.isEmpty else {
            throw RentalCarError.noVehiclesAvailable
        }

        // Sort by daily rate ascending
        return allVehicles.sorted { $0.dailyRate < $1.dailyRate }
    }

    // MARK: - Per-Provider Fetches

    private func fetchVehicles(provider: RentalProvider, params: RentalCarSearchParams) async throws -> [RentalVehicle] {
        switch provider {
        case .enterprise: return try await fetchEnterprise(params: params)
        case .hertz:      return try await fetchHertz(params: params)
        case .national:   return try await fetchNational(params: params)
        }
    }

    // MARK: Enterprise

    private func fetchEnterprise(params: RentalCarSearchParams) async throws -> [RentalVehicle] {
        guard let url = Endpoints.Enterprise.searchURL(
            pickupLocationCode: params.pickupLocation,
            dropoffLocationCode: params.isSameLocation ? params.pickupLocation : params.dropoffLocation,
            pickupDate: params.pickupDateString,
            dropoffDate: params.dropoffDateString
        ) else {
            throw RentalCarError.invalidLocation
        }

        let response: EnterpriseSearchResponse = try await APIClient.shared.get(url: url, headers: Endpoints.Enterprise.headers)
        return response.vehicleGroups.flatMap { group in
            group.vehicles.map { v in
                RentalVehicle(
                    id: v.vehicleId,
                    provider: .enterprise,
                    vehicleClass: mapVehicleClass(from: v.make + " " + v.model),
                    make: v.make,
                    model: v.model,
                    orSimilar: true,
                    passengerCapacity: v.passengerCapacity,
                    baggageCapacity: v.baggageCapacity,
                    isAutomatic: v.transmissionType.lowercased().contains("auto"),
                    hasAirConditioning: v.airConditioning,
                    features: v.features,
                    dailyRate: v.rates.daily,
                    currency: v.rates.currency,
                    totalRate: v.rates.total,
                    taxes: v.rates.taxes,
                    totalWithTaxes: v.rates.total + v.rates.taxes,
                    isRefundable: true,
                    freeMileage: v.rates.unlimitedMileage,
                    mileageRateCents: nil,
                    locationName: params.pickupLocation,
                    locationCode: params.pickupLocation,
                    pickupDate: params.pickupDate,
                    dropoffDate: params.dropoffDate
                )
            }
        }
    }

    // MARK: Hertz

    private func fetchHertz(params: RentalCarSearchParams) async throws -> [RentalVehicle] {
        guard let url = Endpoints.Hertz.searchURL(
            pickupLocation: params.pickupLocation,
            dropoffLocation: params.isSameLocation ? params.pickupLocation : params.dropoffLocation,
            pickupDate: params.pickupDateString,
            dropoffDate: params.dropoffDateString
        ) else {
            throw RentalCarError.invalidLocation
        }

        let response: HertzSearchResponse = try await APIClient.shared.get(url: url, headers: Endpoints.Hertz.headers)
        return response.carGroups.map { g in
            RentalVehicle(
                id: UUID().uuidString,
                provider: .hertz,
                vehicleClass: mapSippToClass(sipp: g.sippCode),
                make: g.make,
                model: g.model,
                orSimilar: true,
                passengerCapacity: g.adultCapacity,
                baggageCapacity: g.bagCapacity,
                isAutomatic: g.automatic,
                hasAirConditioning: g.airConditioning,
                features: g.equipmentOptions,
                dailyRate: g.bestRate.vehicleRateDaily,
                currency: g.bestRate.currency,
                totalRate: g.bestRate.estimatedTotalAmount,
                taxes: g.bestRate.taxesAndFees,
                totalWithTaxes: g.bestRate.estimatedTotalAmount + g.bestRate.taxesAndFees,
                isRefundable: g.bestRate.cancelable,
                freeMileage: g.bestRate.freeMileage,
                mileageRateCents: g.bestRate.mileageRate,
                locationName: params.pickupLocation,
                locationCode: params.pickupLocation,
                pickupDate: params.pickupDate,
                dropoffDate: params.dropoffDate
            )
        }
    }

    // MARK: National

    private func fetchNational(params: RentalCarSearchParams) async throws -> [RentalVehicle] {
        guard let url = Endpoints.National.searchURL(
            pickupLocation: params.pickupLocation,
            dropoffLocation: params.isSameLocation ? params.pickupLocation : params.dropoffLocation,
            pickupDate: params.pickupDateString,
            dropoffDate: params.dropoffDateString
        ) else {
            throw RentalCarError.invalidLocation
        }

        let response: NationalSearchResponse = try await APIClient.shared.get(url: url, headers: Endpoints.National.headers)
        return response.availableVehicles.map { v in
            RentalVehicle(
                id: v.vehicleId,
                provider: .national,
                vehicleClass: mapVehicleClassString(v.carClass),
                make: v.make,
                model: v.model,
                orSimilar: true,
                passengerCapacity: v.passengerCount,
                baggageCapacity: v.luggage,
                isAutomatic: v.transmissionAutomatic,
                hasAirConditioning: v.acAvailable,
                features: v.vehicleFeatures,
                dailyRate: v.priceInfo.perDayRate,
                currency: v.priceInfo.currencyCode,
                totalRate: v.priceInfo.totalCost,
                taxes: v.priceInfo.totalTaxes,
                totalWithTaxes: v.priceInfo.totalCost + v.priceInfo.totalTaxes,
                isRefundable: v.priceInfo.fullyRefundable,
                freeMileage: v.priceInfo.unlimitedMileage,
                mileageRateCents: v.priceInfo.perMileCharge,
                locationName: params.pickupLocation,
                locationCode: params.pickupLocation,
                pickupDate: params.pickupDate,
                dropoffDate: params.dropoffDate
            )
        }
    }

    // MARK: - Helpers

    /// Maps a loose vehicle description string to a VehicleClass.
    private func mapVehicleClass(from description: String) -> VehicleClass {
        let lower = description.lowercased()
        if lower.contains("econom") || lower.contains("mini")   { return .economy }
        if lower.contains("compact")                            { return .compact }
        if lower.contains("mid") || lower.contains("inter")    { return .midsize }
        if lower.contains("full") || lower.contains("stand")   { return .fullsize }
        if lower.contains("suv") || lower.contains("crossover") { return .suv }
        if lower.contains("luxury") || lower.contains("premium") { return .luxury }
        if lower.contains("van") || lower.contains("minivan")  { return .van }
        if lower.contains("truck") || lower.contains("pickup") { return .truck }
        return .midsize
    }

    /// Maps a National car class string (e.g. "ECONOMY") to VehicleClass.
    private func mapVehicleClassString(_ classString: String) -> VehicleClass {
        mapVehicleClass(from: classString)
    }

    /// Maps Hertz SIPP code first character to VehicleClass.
    /// SIPP: M=Mini, E=Economy, C=Compact, I=Intermediate, S=Standard,
    ///       F=Full, P=Premium, L=Luxury, X=SUV, V=Van, T=Truck
    private func mapSippToClass(sipp: String) -> VehicleClass {
        guard let first = sipp.first else { return .midsize }
        switch first {
        case "M", "N":      return .economy
        case "E":           return .economy
        case "C", "H":      return .compact
        case "I", "U":      return .midsize
        case "S", "R":      return .fullsize
        case "F", "G":      return .fullsize
        case "P", "L", "W": return .luxury
        case "X", "Y", "J": return .suv
        case "V", "Z":      return .van
        case "T", "K":      return .truck
        default:            return .midsize
        }
    }
}
