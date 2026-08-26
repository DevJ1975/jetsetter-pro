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

        // Fan out to each requested provider concurrently.
        //
        // A single flaky partner (timeout, 500, decode failure) must NOT hide
        // inventory that the other providers returned successfully. So each
        // per-provider fetch is wrapped to return [] on failure instead of
        // throwing — the group never aborts, and we only surface an error when
        // EVERY provider came back empty (all failed or genuinely no cars).
        var allVehicles: [RentalVehicle] = []
        await withTaskGroup(of: [RentalVehicle].self) { group in
            for provider in params.providers {
                group.addTask {
                    do {
                        return try await self.fetchVehicles(provider: provider, params: params)
                    } catch {
                        // Swallow this provider's failure so partial results survive.
                        return []
                    }
                }
            }
            for await vehicles in group {
                allVehicles.append(contentsOf: vehicles)
            }
        }

        guard !allVehicles.isEmpty else {
            throw RentalCarError.noVehiclesAvailable
        }

        // Sort by daily rate ascending.
        //
        // Providers may quote in different currencies (e.g. JPY from a
        // Tokyo provider vs USD from another), so comparing raw `dailyRate`
        // values across currencies is meaningless. Normalise each rate into
        // a single comparison currency before sorting.
        return await sortedByNormalisedDailyRate(allVehicles)
    }

    /// Sorts vehicles by daily rate ascending, normalising mixed currencies
    /// into a single comparison currency via `ExchangeRateService`.
    ///
    /// If every vehicle already shares one currency, no conversion is needed.
    /// If FX rates are unavailable (offline with no cache), we fall back to
    /// grouping by currency and sorting within each group, so we never
    /// directly compare raw amounts across different currencies.
    private func sortedByNormalisedDailyRate(_ vehicles: [RentalVehicle]) async -> [RentalVehicle] {
        // Distinct currencies present in the result set (normalised to upper-case).
        let currencies = Set(vehicles.map { $0.currency.uppercased() })

        // Single currency — a plain numeric sort is already correct.
        guard currencies.count > 1 else {
            return vehicles.sorted { $0.dailyRate < $1.dailyRate }
        }

        // Choose the most common currency as the comparison base (ties broken
        // deterministically), then fetch base -> X rates for it.
        let base = mostCommonCurrency(in: vehicles)
        if let rates = await ExchangeRateService.shared.rates(for: base) {
            return vehicles.sorted {
                normalisedRate($0, base: base, rates: rates)
                    < normalisedRate($1, base: base, rates: rates)
            }
        }

        // No FX data available — group by currency and sort within each group
        // rather than comparing raw amounts across currencies.
        return vehicles.sorted {
            let lhsCurrency = $0.currency.uppercased()
            let rhsCurrency = $1.currency.uppercased()
            if lhsCurrency != rhsCurrency {
                return lhsCurrency < rhsCurrency
            }
            return $0.dailyRate < $1.dailyRate
        }
    }

    /// Converts a vehicle's daily rate into the comparison `base` currency.
    /// `rates` maps base -> other currency, so a rate quoted in currency `C`
    /// is divided by the base->C rate to express it in the base currency.
    /// Returns `.greatestFiniteMagnitude` when the currency can't be converted
    /// so unknown-currency vehicles sort last instead of corrupting the order.
    private func normalisedRate(_ vehicle: RentalVehicle, base: String, rates: ExchangeRates) -> Double {
        let currency = vehicle.currency.uppercased()
        if currency == base.uppercased() {
            return vehicle.dailyRate
        }
        guard let rate = rates.rates[currency], rate > 0 else {
            return .greatestFiniteMagnitude
        }
        return vehicle.dailyRate / rate
    }

    /// Returns the currency that appears most often across `vehicles`,
    /// breaking ties alphabetically for deterministic output.
    private func mostCommonCurrency(in vehicles: [RentalVehicle]) -> String {
        var counts: [String: Int] = [:]
        for vehicle in vehicles {
            counts[vehicle.currency.uppercased(), default: 0] += 1
        }
        return counts.max {
            $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key
        }?.key ?? "USD"
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
                id: "hertz-\(g.sippCode)-\(g.make)-\(g.model)",
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
