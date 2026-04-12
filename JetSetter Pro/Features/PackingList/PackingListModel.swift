// File: Features/PackingList/PackingListModel.swift
// Models for the Smart Packing List feature (Feature 2).
// Auto-generates a packing list using: WeatherKit forecast, trip duration,
// NLP activity detection, airline baggage rules, and Claude AI.
//
// Supabase table:
//   CREATE TABLE packing_lists (
//     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
//     user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
//     trip_id uuid NOT NULL UNIQUE,
//     items jsonb DEFAULT '[]'::jsonb,
//     generated_at timestamptz DEFAULT now(),
//     created_at timestamptz DEFAULT now()
//   );
//   ALTER TABLE packing_lists ENABLE ROW LEVEL SECURITY;
//   CREATE POLICY "user_packing" ON packing_lists FOR ALL USING (auth.uid() = user_id);

import Foundation

// MARK: - PackingCategory

/// Top-level category groupings shown as collapsible sections in the UI.
enum PackingCategory: String, Codable, CaseIterable, Identifiable {
    case clothing    = "Clothing"
    case toiletries  = "Toiletries"
    case electronics = "Electronics"
    case documents   = "Documents"
    case health      = "Health"
    case misc        = "Misc"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .clothing:    return "tshirt.fill"
        case .toiletries:  return "drop.fill"
        case .electronics: return "bolt.fill"
        case .documents:   return "doc.fill"
        case .health:      return "cross.case.fill"
        case .misc:        return "bag.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .clothing:    return "#3B9EF0"
        case .toiletries:  return "#1DB97D"
        case .electronics: return "#E8A020"
        case .documents:   return "#7B3FBF"
        case .health:      return "#E84040"
        case .misc:        return "#8B92A8"
        }
    }
}

// MARK: - SmartPackingItem

/// A single item in the AI-generated packing list.
struct SmartPackingItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var category: PackingCategory
    var isPacked: Bool
    var isCustom: Bool          // false = AI-generated, true = user-added
    var quantity: Int           // e.g. 3 for "3 pairs of socks"
    var notes: String?          // AI reason or user note

    init(
        id: UUID = UUID(),
        name: String,
        category: PackingCategory,
        isPacked: Bool = false,
        isCustom: Bool = false,
        quantity: Int = 1,
        notes: String? = nil
    ) {
        self.id       = id
        self.name     = name
        self.category = category
        self.isPacked = isPacked
        self.isCustom = isCustom
        self.quantity = quantity
        self.notes    = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, quantity, notes
        case isPacked  = "is_packed"
        case isCustom  = "is_custom"
    }
}

// MARK: - PackingListResult

/// The full packing list for one trip, stored in Supabase `packing_lists`.
struct PackingListResult: Identifiable, Codable {
    let id: UUID
    var tripId: UUID
    var items: [SmartPackingItem]
    var generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, items
        case tripId     = "trip_id"
        case generatedAt = "generated_at"
    }

    /// Completion ratio (0.0–1.0) for the progress ring.
    var completionRatio: Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.filter { $0.isPacked }.count) / Double(items.count)
    }

    /// Items grouped by category, preserving CaseIterable order.
    var groupedByCategory: [(category: PackingCategory, items: [SmartPackingItem])] {
        PackingCategory.allCases.compactMap { cat in
            let catItems = items.filter { $0.category == cat }
            return catItems.isEmpty ? nil : (category: cat, items: catItems)
        }
    }
}

// MARK: - Trip Type

enum TripType: String, Codable, CaseIterable, Identifiable {
    case business = "business"
    case leisure  = "leisure"
    case mixed    = "mixed"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

// MARK: - Airline Baggage Rules

/// Hardcoded baggage allowances for 20 major airlines.
/// Used to tailor packing list recommendations to available luggage space.
struct AirlineBaggageRule {
    let airlineName: String
    let iataCode: String
    let carryOnWeightKg: Int
    let checkedBagWeightKg: Int
    let personalItemAllowed: Bool
    let freeBagsIncluded: Int
}

extension AirlineBaggageRule {
    static let rules: [String: AirlineBaggageRule] = [
        "UA": AirlineBaggageRule(airlineName: "United Airlines",    iataCode: "UA", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 0),
        "DL": AirlineBaggageRule(airlineName: "Delta Air Lines",    iataCode: "DL", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 0),
        "AA": AirlineBaggageRule(airlineName: "American Airlines",  iataCode: "AA", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 0),
        "WN": AirlineBaggageRule(airlineName: "Southwest Airlines", iataCode: "WN", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 2),
        "B6": AirlineBaggageRule(airlineName: "JetBlue",            iataCode: "B6", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 0),
        "AS": AirlineBaggageRule(airlineName: "Alaska Airlines",    iataCode: "AS", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 0),
        "NK": AirlineBaggageRule(airlineName: "Spirit Airlines",    iataCode: "NK", carryOnWeightKg: 8,  checkedBagWeightKg: 18, personalItemAllowed: true,  freeBagsIncluded: 0),
        "F9": AirlineBaggageRule(airlineName: "Frontier Airlines",  iataCode: "F9", carryOnWeightKg: 10, checkedBagWeightKg: 20, personalItemAllowed: true,  freeBagsIncluded: 0),
        "BA": AirlineBaggageRule(airlineName: "British Airways",    iataCode: "BA", carryOnWeightKg: 23, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 1),
        "LH": AirlineBaggageRule(airlineName: "Lufthansa",          iataCode: "LH", carryOnWeightKg: 8,  checkedBagWeightKg: 23, personalItemAllowed: false, freeBagsIncluded: 1),
        "AF": AirlineBaggageRule(airlineName: "Air France",         iataCode: "AF", carryOnWeightKg: 12, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 1),
        "EK": AirlineBaggageRule(airlineName: "Emirates",           iataCode: "EK", carryOnWeightKg: 7,  checkedBagWeightKg: 30, personalItemAllowed: true,  freeBagsIncluded: 1),
        "QR": AirlineBaggageRule(airlineName: "Qatar Airways",      iataCode: "QR", carryOnWeightKg: 7,  checkedBagWeightKg: 30, personalItemAllowed: false, freeBagsIncluded: 1),
        "SQ": AirlineBaggageRule(airlineName: "Singapore Airlines", iataCode: "SQ", carryOnWeightKg: 7,  checkedBagWeightKg: 30, personalItemAllowed: false, freeBagsIncluded: 1),
        "AC": AirlineBaggageRule(airlineName: "Air Canada",         iataCode: "AC", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 0),
        "NH": AirlineBaggageRule(airlineName: "ANA",                iataCode: "NH", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: false, freeBagsIncluded: 1),
        "JL": AirlineBaggageRule(airlineName: "Japan Airlines",     iataCode: "JL", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: false, freeBagsIncluded: 1),
        "KE": AirlineBaggageRule(airlineName: "Korean Air",         iataCode: "KE", carryOnWeightKg: 10, checkedBagWeightKg: 23, personalItemAllowed: false, freeBagsIncluded: 1),
        "LA": AirlineBaggageRule(airlineName: "LATAM Airlines",     iataCode: "LA", carryOnWeightKg: 8,  checkedBagWeightKg: 23, personalItemAllowed: true,  freeBagsIncluded: 0),
        "TK": AirlineBaggageRule(airlineName: "Turkish Airlines",   iataCode: "TK", carryOnWeightKg: 8,  checkedBagWeightKg: 23, personalItemAllowed: false, freeBagsIncluded: 1)
    ]
}
