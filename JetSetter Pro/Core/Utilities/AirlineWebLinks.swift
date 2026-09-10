// File: Core/Utilities/AirlineWebLinks.swift
//
// Airline home pages, keyed by IATA code and by common name fragments. Used
// wherever the app hands the traveler to the airline itself (baggage status,
// a delayed-bag report) instead of pretending to have carrier data. Only
// site roots are listed: deep baggage URLs change often and a 404 in a beta
// is worse than one extra tap.

import Foundation

enum AirlineWebLinks {

    private struct Entry {
        let code: String
        let names: [String]     // lowercase fragments matched against free text
        let host: String
    }

    private static let entries: [Entry] = [
        Entry(code: "UA", names: ["united"],             host: "https://www.united.com"),
        Entry(code: "DL", names: ["delta"],              host: "https://www.delta.com"),
        Entry(code: "AA", names: ["american"],           host: "https://www.aa.com"),
        Entry(code: "WN", names: ["southwest"],          host: "https://www.southwest.com"),
        Entry(code: "B6", names: ["jetblue"],            host: "https://www.jetblue.com"),
        Entry(code: "AS", names: ["alaska"],             host: "https://www.alaskaair.com"),
        Entry(code: "NK", names: ["spirit"],             host: "https://www.spirit.com"),
        Entry(code: "F9", names: ["frontier"],           host: "https://www.flyfrontier.com"),
        Entry(code: "HA", names: ["hawaiian"],           host: "https://www.hawaiianairlines.com"),
        Entry(code: "G4", names: ["allegiant"],          host: "https://www.allegiantair.com"),
        Entry(code: "BA", names: ["british airways"],    host: "https://www.britishairways.com"),
        Entry(code: "AF", names: ["air france"],         host: "https://www.airfrance.com"),
        Entry(code: "LH", names: ["lufthansa"],          host: "https://www.lufthansa.com"),
        Entry(code: "EK", names: ["emirates"],           host: "https://www.emirates.com"),
        Entry(code: "QR", names: ["qatar"],              host: "https://www.qatarairways.com"),
        Entry(code: "AC", names: ["air canada"],         host: "https://www.aircanada.com"),
        Entry(code: "WS", names: ["westjet"],            host: "https://www.westjet.com"),
        Entry(code: "LA", names: ["latam"],              host: "https://www.latamairlines.com"),
        Entry(code: "AV", names: ["avianca"],            host: "https://www.avianca.com"),
        Entry(code: "KL", names: ["klm"],                host: "https://www.klm.com")
    ]

    /// Resolves an airline from a name ("Delta Air Lines"), an IATA code ("DL"),
    /// or a flight number ("DL445"). Returns nil when the carrier is unknown.
    static func homepage(for airlineOrFlight: String?) -> URL? {
        guard let raw = airlineOrFlight?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if let byName = entries.first(where: { entry in entry.names.contains { lower.contains($0) } }) {
            return URL(string: byName.host)
        }
        // Only read a code out of something shaped like one ("DL", "DL445",
        // "B6 715"); "Bangkok Airways" must not become British Airways.
        let upper = raw.uppercased().replacingOccurrences(of: " ", with: "")
        guard upper.range(of: #"^[A-Z0-9]{2,3}\d{0,4}$"#, options: .regularExpression) != nil else { return nil }
        let code = String(upper.prefix(2))
        if let byCode = entries.first(where: { $0.code == code }) {
            return URL(string: byCode.host)
        }
        return nil
    }

    /// Display name for a known code, e.g. "DL" → "Delta".
    static func displayName(forCode code: String) -> String? {
        entries.first { $0.code == code.uppercased() }?.names.first?.capitalized
    }
}
