// File: Features/LoyaltyVault/LoyaltyModel.swift

import Foundation
import SwiftUI

// MARK: - Program Catalog

/// Curated list of common frequent-flyer and hotel programs.
enum LoyaltyProgramCatalog {

    struct Program: Identifiable, Hashable {
        let id: String
        let name: String
        let brandHex: String
        let kind: LoyaltyKind
    }

    static let all: [Program] = [
        // Airlines (US)
        .init(id: "UA",       name: "United MileagePlus",     brandHex: "#005DAA", kind: .airline),
        .init(id: "AA",       name: "American AAdvantage",    brandHex: "#0078D2", kind: .airline),
        .init(id: "DL",       name: "Delta SkyMiles",          brandHex: "#E01933", kind: .airline),
        .init(id: "WN",       name: "Southwest Rapid Rewards", brandHex: "#304CB2", kind: .airline),
        .init(id: "AS",       name: "Alaska Mileage Plan",     brandHex: "#01426A", kind: .airline),
        .init(id: "B6",       name: "JetBlue TrueBlue",        brandHex: "#003876", kind: .airline),
        .init(id: "NK",       name: "Spirit Free Spirit",      brandHex: "#FFEB00", kind: .airline),
        // Airlines (International)
        .init(id: "BA",       name: "British Airways Executive Club", brandHex: "#075AAA", kind: .airline),
        .init(id: "AF",       name: "Air France Flying Blue",  brandHex: "#002B7F", kind: .airline),
        .init(id: "LH",       name: "Lufthansa Miles & More",  brandHex: "#05164D", kind: .airline),
        .init(id: "EK",       name: "Emirates Skywards",       brandHex: "#D71921", kind: .airline),
        .init(id: "QR",       name: "Qatar Privilege Club",    brandHex: "#5C0931", kind: .airline),
        .init(id: "SQ",       name: "Singapore KrisFlyer",     brandHex: "#FED141", kind: .airline),
        .init(id: "CX",       name: "Cathay Pacific",          brandHex: "#006564", kind: .airline),
        .init(id: "JL",       name: "JAL Mileage Bank",        brandHex: "#E60012", kind: .airline),
        .init(id: "NH",       name: "ANA Mileage Club",        brandHex: "#13448F", kind: .airline),
        .init(id: "QF",       name: "Qantas Frequent Flyer",   brandHex: "#EE0000", kind: .airline),
        // Hotels
        .init(id: "MARRIOTT", name: "Marriott Bonvoy",         brandHex: "#1F2D3D", kind: .hotel),
        .init(id: "HILTON",   name: "Hilton Honors",           brandHex: "#0072BC", kind: .hotel),
        .init(id: "IHG",      name: "IHG One Rewards",         brandHex: "#003C7E", kind: .hotel),
        .init(id: "HYATT",    name: "World of Hyatt",          brandHex: "#00264A", kind: .hotel),
        .init(id: "ACCOR",    name: "Accor ALL",               brandHex: "#FFD800", kind: .hotel),
        .init(id: "WYNDHAM",  name: "Wyndham Rewards",         brandHex: "#A41E34", kind: .hotel),
        .init(id: "CHOICE",   name: "Choice Privileges",       brandHex: "#0094CA", kind: .hotel),
        // Rental
        .init(id: "HERTZ_GR", name: "Hertz Gold Plus Rewards", brandHex: "#FFD300", kind: .rentalCar),
        .init(id: "AVIS_PR",  name: "Avis Preferred",          brandHex: "#D4001A", kind: .rentalCar),
        .init(id: "NATIONAL", name: "National Emerald Club",   brandHex: "#1B8B3C", kind: .rentalCar)
    ]

    static func find(id: String) -> Program? {
        all.first { $0.id == id }
    }
}

enum LoyaltyKind: String, Codable, CaseIterable {
    case airline, hotel, rentalCar

    var displayName: String {
        switch self {
        case .airline:   return "Airline"
        case .hotel:     return "Hotel"
        case .rentalCar: return "Rental Car"
        }
    }

    var systemImage: String {
        switch self {
        case .airline:   return "airplane"
        case .hotel:     return "bed.double.fill"
        case .rentalCar: return "car.fill"
        }
    }
}

// MARK: - Account

struct LoyaltyAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var programID: String
    var memberNumber: String
    var memberSince: Date?
    var balance: Int
    var tier: String     // e.g. "Silver", "Gold", "Platinum", "Diamond"
    var tierExpiration: Date?
    var notes: String?

    init(
        id: UUID = UUID(),
        programID: String,
        memberNumber: String,
        memberSince: Date? = nil,
        balance: Int = 0,
        tier: String = "",
        tierExpiration: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.programID = programID
        self.memberNumber = memberNumber
        self.memberSince = memberSince
        self.balance = balance
        self.tier = tier
        self.tierExpiration = tierExpiration
        self.notes = notes
    }
}
