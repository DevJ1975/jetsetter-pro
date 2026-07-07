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
        if MockDataService.isEnabled {
            return Self.demoTokyoVehicles(pickupDate: params.pickupDate, dropoffDate: params.dropoffDate)
        }

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

    // MARK: - Demo Data (Investor Demo Mode)

    /// Returns 5 hand-curated Tokyo (NRT) rental vehicles for investor demo mode.
    /// Used when `MockDataService.isEnabled == true` to bypass network calls.
    static func demoTokyoVehicles(pickupDate: Date, dropoffDate: Date) -> [RentalVehicle] {
        let locationName = "NRT — Terminal 1 Arrivals"
        let locationCode = "NRT"

        return [
            RentalVehicle(
                id: "DEMO-HZ-LEXUS-ES",
                provider: .hertz,
                vehicleClass: .luxury,           // Premium
                make: "Lexus",
                model: "ES Hybrid",
                orSimilar: true,
                passengerCapacity: 4,
                baggageCapacity: 3,
                isAutomatic: true,
                hasAirConditioning: true,
                features: ["Hybrid", "Apple CarPlay", "Heated seats"],
                dailyRate: 89.0,
                currency: "USD",
                totalRate: 445.0,
                taxes: 67.0,
                totalWithTaxes: 512.0,
                isRefundable: true,
                freeMileage: true,
                mileageRateCents: nil,
                locationName: locationName,
                locationCode: locationCode,
                pickupDate: pickupDate,
                dropoffDate: dropoffDate
            ),
            RentalVehicle(
                id: "DEMO-HZ-MB-CCLASS",
                provider: .hertz,
                vehicleClass: .luxury,           // Luxury
                make: "Mercedes-Benz",
                model: "C-Class",
                orSimilar: true,
                passengerCapacity: 5,
                baggageCapacity: 3,
                isAutomatic: true,
                hasAirConditioning: true,
                features: ["Leather", "Navigation", "Apple CarPlay"],
                dailyRate: 129.0,
                currency: "USD",
                totalRate: 645.0,
                taxes: 97.0,
                totalWithTaxes: 742.0,
                isRefundable: true,
                freeMileage: true,
                mileageRateCents: nil,
                locationName: locationName,
                locationCode: locationCode,
                pickupDate: pickupDate,
                dropoffDate: dropoffDate
            ),
            RentalVehicle(
                id: "DEMO-ENT-CAMRY",
                provider: .enterprise,
                vehicleClass: .fullsize,         // Standard
                make: "Toyota",
                model: "Camry",
                orSimilar: true,
                passengerCapacity: 5,
                baggageCapacity: 3,
                isAutomatic: true,
                hasAirConditioning: true,
                features: ["Bluetooth", "Backup Camera", "USB-C"],
                dailyRate: 52.0,
                currency: "USD",
                totalRate: 260.0,
                taxes: 39.0,
                totalWithTaxes: 299.0,
                isRefundable: true,
                freeMileage: true,
                mileageRateCents: nil,
                locationName: locationName,
                locationCode: locationCode,
                pickupDate: pickupDate,
                dropoffDate: dropoffDate
            ),
            RentalVehicle(
                id: "DEMO-NAT-TAHOE",
                provider: .national,
                vehicleClass: .suv,              // SUV
                make: "Chevrolet",
                model: "Tahoe",
                orSimilar: true,
                passengerCapacity: 7,
                baggageCapacity: 5,
                isAutomatic: true,
                hasAirConditioning: true,
                features: ["3rd row seating", "4WD"],
                dailyRate: 98.0,
                currency: "USD",
                totalRate: 490.0,
                taxes: 73.0,
                totalWithTaxes: 563.0,
                isRefundable: true,
                freeMileage: true,
                mileageRateCents: nil,
                locationName: locationName,
                locationCode: locationCode,
                pickupDate: pickupDate,
                dropoffDate: dropoffDate
            ),
            RentalVehicle(
                id: "DEMO-NAT-MUSTANG",
                provider: .national,
                vehicleClass: .fullsize,         // Sport (no .sport case; closest fit)
                make: "Ford",
                model: "Mustang Convertible",
                orSimilar: true,
                passengerCapacity: 4,
                baggageCapacity: 2,
                isAutomatic: true,
                hasAirConditioning: true,
                features: ["Convertible", "Sport mode"],
                dailyRate: 74.0,
                currency: "USD",
                totalRate: 370.0,
                taxes: 55.0,
                totalWithTaxes: 425.0,
                isRefundable: true,
                freeMileage: true,
                mileageRateCents: nil,
                locationName: locationName,
                locationCode: locationCode,
                pickupDate: pickupDate,
                dropoffDate: dropoffDate
            )
        ]
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
