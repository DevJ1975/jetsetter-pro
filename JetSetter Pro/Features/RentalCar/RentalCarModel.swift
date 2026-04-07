// File: Features/RentalCar/RentalCarModel.swift

import Foundation

// MARK: - Rental Provider

enum RentalProvider: String, CaseIterable, Codable {
    case enterprise = "enterprise"
    case hertz      = "hertz"
    case national   = "national"

    var displayName: String {
        switch self {
        case .enterprise: return "Enterprise"
        case .hertz:      return "Hertz"
        case .national:   return "National"
        }
    }

    /// SF Symbol name for each provider (generic car icon per brand)
    var systemImage: String {
        switch self {
        case .enterprise: return "car.fill"
        case .hertz:      return "car.side.fill"
        case .national:   return "car.side.rear.and.front.and.person.fill"
        }
    }

    /// Brand accent colour (hex)
    var colorHex: String {
        switch self {
        case .enterprise: return "#006400"  // Enterprise green
        case .hertz:      return "#FFD700"  // Hertz gold
        case .national:   return "#CC0000"  // National red
        }
    }

    /// URL scheme used for the provider's iOS app deep link
    var appScheme: String {
        switch self {
        case .enterprise: return Endpoints.Enterprise.appScheme
        case .hertz:      return Endpoints.Hertz.appScheme
        case .national:   return Endpoints.National.appScheme
        }
    }

    var appStoreURL: URL? {
        switch self {
        case .enterprise: return Endpoints.Enterprise.appStoreURL
        case .hertz:      return Endpoints.Hertz.appStoreURL
        case .national:   return Endpoints.National.appStoreURL
        }
    }
}

// MARK: - Vehicle Class

enum VehicleClass: String, CaseIterable, Codable {
    case economy    = "economy"
    case compact    = "compact"
    case midsize    = "midsize"
    case fullsize   = "fullsize"
    case suv        = "suv"
    case luxury     = "luxury"
    case van        = "van"
    case truck      = "truck"

    var displayName: String {
        switch self {
        case .economy:  return "Economy"
        case .compact:  return "Compact"
        case .midsize:  return "Mid-Size"
        case .fullsize: return "Full-Size"
        case .suv:      return "SUV"
        case .luxury:   return "Luxury"
        case .van:      return "Van"
        case .truck:    return "Truck"
        }
    }

    var systemImage: String {
        switch self {
        case .economy, .compact:          return "car"
        case .midsize, .fullsize:         return "car.fill"
        case .suv:                        return "car.side.fill"
        case .luxury:                     return "car.side.and.exclamationmark"
        case .van:                        return "bus"
        case .truck:                      return "truck.box"
        }
    }
}

// MARK: - Rental Vehicle

struct RentalVehicle: Identifiable, Codable {
    let id: String
    let provider: RentalProvider
    let vehicleClass: VehicleClass
    let make: String
    let model: String
    /// e.g. "or similar"
    let orSimilar: Bool
    let passengerCapacity: Int
    let baggageCapacity: Int
    let isAutomatic: Bool
    let hasAirConditioning: Bool
    let features: [String]            // e.g. ["GPS", "Bluetooth", "Backup Camera"]
    let dailyRate: Double
    let currency: String
    let totalRate: Double             // dailyRate × numberOfDays
    let taxes: Double
    let totalWithTaxes: Double
    let isRefundable: Bool
    let freeMileage: Bool
    let mileageRateCents: Int?        // cents per mile if not free, else nil
    let locationName: String          // e.g. "O'Hare International Airport"
    let locationCode: String          // e.g. "CHIA3"
    let pickupDate: Date
    let dropoffDate: Date

    // MARK: Computed

    var numberOfDays: Int {
        let diff = Calendar.current.dateComponents([.day], from: pickupDate, to: dropoffDate)
        return max(diff.day ?? 1, 1)
    }

    var formattedDailyRate: String {
        dailyRate.formatted(.currency(code: currency))
    }

    var formattedTotalWithTaxes: String {
        totalWithTaxes.formatted(.currency(code: currency))
    }

    var formattedTaxes: String {
        taxes.formatted(.currency(code: currency))
    }

    var displayName: String {
        orSimilar ? "\(make) \(model) or Similar" : "\(make) \(model)"
    }

    var mileageDescription: String {
        if freeMileage { return "Unlimited miles" }
        guard let cents = mileageRateCents else { return "Mileage fees may apply" }
        let dollarRate = Double(cents) / 100.0
        return String(format: "$%.2f/mile after limit", dollarRate)
    }

    /// Deep link URL to open the provider's app pre-filled with location + dates.
    /// Falls back to App Store URL if the scheme format cannot be built.
    func deepLinkURL() -> URL? {
        // Each provider uses its own URL scheme format.
        // These open the app to a search results page when installed.
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let pickup = dateFormatter.string(from: pickupDate)
        let dropoff = dateFormatter.string(from: dropoffDate)

        switch provider {
        case .enterprise:
            return URL(string: "enterprise://search?location=\(locationCode)&pickup=\(pickup)&dropoff=\(dropoff)")
        case .hertz:
            return URL(string: "hertz://reservation?pickup=\(locationCode)&pudate=\(pickup)&dodate=\(dropoff)")
        case .national:
            return URL(string: "nationalcar://search?loc=\(locationCode)&start=\(pickup)&end=\(dropoff)")
        }
    }
}

// MARK: - Search Parameters

struct RentalCarSearchParams {
    var pickupLocation: String = ""
    var dropoffLocation: String = ""       // empty = same as pickup
    var pickupDate: Date = .now
    var dropoffDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    var vehicleClass: VehicleClass? = nil  // nil = any class
    var providers: [RentalProvider] = RentalProvider.allCases

    var isSameLocation: Bool { dropoffLocation.isEmpty || dropoffLocation == pickupLocation }

    var numberOfDays: Int {
        let diff = Calendar.current.dateComponents([.day], from: pickupDate, to: dropoffDate)
        return max(diff.day ?? 1, 1)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    var pickupDateString: String { Self.dateFormatter.string(from: pickupDate) }
    var dropoffDateString: String { Self.dateFormatter.string(from: dropoffDate) }
}

// MARK: - API Response Models (normalized across providers)

/// Generic vehicle availability response — each provider's service maps to this.
struct RentalCarSearchResponse: Codable {
    let vehicles: [RentalVehicle]
}

// MARK: - Enterprise API Response Shape

struct EnterpriseSearchResponse: Codable {
    let vehicleGroups: [EnterpriseVehicleGroup]

    struct EnterpriseVehicleGroup: Codable {
        let groupCode: String
        let description: String
        let vehicles: [EnterpriseVehicle]
    }

    struct EnterpriseVehicle: Codable {
        let vehicleId: String
        let make: String
        let model: String
        let passengerCapacity: Int
        let baggageCapacity: Int
        let transmissionType: String
        let airConditioning: Bool
        let features: [String]
        let rates: EnterpriseRates

        struct EnterpriseRates: Codable {
            let daily: Double
            let total: Double
            let taxes: Double
            let currency: String
            let unlimitedMileage: Bool
        }
    }
}

// MARK: - Hertz API Response Shape

struct HertzSearchResponse: Codable {
    let carGroups: [HertzCarGroup]

    struct HertzCarGroup: Codable {
        let sippCode: String          // Standard Interline Passenger Procedures (SIPP) code
        let vehicleName: String
        let make: String
        let model: String
        let adultCapacity: Int
        let bagCapacity: Int
        let automatic: Bool
        let airConditioning: Bool
        let equipmentOptions: [String]
        let bestRate: HertzRate

        struct HertzRate: Codable {
            let vehicleRateDaily: Double
            let estimatedTotalAmount: Double
            let taxesAndFees: Double
            let currency: String
            let freeMileage: Bool
            let mileageRate: Int?     // cents per mile
            let cancelable: Bool
        }
    }
}

// MARK: - National API Response Shape

struct NationalSearchResponse: Codable {
    let availableVehicles: [NationalVehicle]

    struct NationalVehicle: Codable {
        let vehicleId: String
        let carClass: String
        let vehicleName: String
        let make: String
        let model: String
        let passengerCount: Int
        let luggage: Int
        let transmissionAutomatic: Bool
        let acAvailable: Bool
        let vehicleFeatures: [String]
        let priceInfo: NationalPriceInfo

        struct NationalPriceInfo: Codable {
            let perDayRate: Double
            let totalCost: Double
            let totalTaxes: Double
            let currencyCode: String
            let unlimitedMileage: Bool
            let perMileCharge: Int?
            let fullyRefundable: Bool
        }
    }
}

// MARK: - Sample Data

extension RentalVehicle {
    static let sampleEconomy = RentalVehicle(
        id: "EV001",
        provider: .enterprise,
        vehicleClass: .economy,
        make: "Toyota",
        model: "Corolla",
        orSimilar: true,
        passengerCapacity: 5,
        baggageCapacity: 2,
        isAutomatic: true,
        hasAirConditioning: true,
        features: ["Bluetooth", "USB-C", "Backup Camera"],
        dailyRate: 42.99,
        currency: "USD",
        totalRate: 128.97,
        taxes: 18.50,
        totalWithTaxes: 147.47,
        isRefundable: true,
        freeMileage: true,
        mileageRateCents: nil,
        locationName: "O'Hare International Airport",
        locationCode: "CHIA3",
        pickupDate: Date(),
        dropoffDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    )

    static let sampleSUV = RentalVehicle(
        id: "HV002",
        provider: .hertz,
        vehicleClass: .suv,
        make: "Ford",
        model: "Explorer",
        orSimilar: true,
        passengerCapacity: 7,
        baggageCapacity: 4,
        isAutomatic: true,
        hasAirConditioning: true,
        features: ["GPS", "Bluetooth", "Apple CarPlay", "Heated Seats"],
        dailyRate: 79.99,
        currency: "USD",
        totalRate: 239.97,
        taxes: 35.00,
        totalWithTaxes: 274.97,
        isRefundable: false,
        freeMileage: false,
        mileageRateCents: 35,
        locationName: "O'Hare International Airport",
        locationCode: "CHIA3",
        pickupDate: Date(),
        dropoffDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    )

    static let sampleLuxury = RentalVehicle(
        id: "NV003",
        provider: .national,
        vehicleClass: .luxury,
        make: "BMW",
        model: "5 Series",
        orSimilar: false,
        passengerCapacity: 5,
        baggageCapacity: 3,
        isAutomatic: true,
        hasAirConditioning: true,
        features: ["GPS", "Bluetooth", "Apple CarPlay", "Heated Seats", "Sunroof", "Leather Seats"],
        dailyRate: 129.99,
        currency: "USD",
        totalRate: 389.97,
        taxes: 55.00,
        totalWithTaxes: 444.97,
        isRefundable: true,
        freeMileage: true,
        mileageRateCents: nil,
        locationName: "O'Hare International Airport",
        locationCode: "CHIA3",
        pickupDate: Date(),
        dropoffDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    )

    static let samples: [RentalVehicle] = [.sampleEconomy, .sampleSUV, .sampleLuxury]
}
