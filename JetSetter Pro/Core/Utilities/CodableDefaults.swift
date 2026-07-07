// File: Core/Utilities/CodableDefaults.swift
//
// Generic Codable-over-UserDefaults persistence. Most on-device stores
// (itinerary, luggage, packing list, expenses, wallet) hand-rolled the same
// three-step flow: read Data for a key, decode with an `.iso8601` JSONDecoder
// (silently returning a default on failure), and — to save — encode with an
// `.iso8601` JSONEncoder and write the Data back. This centralizes that flow so
// the strategy and the "tolerate a decode failure" policy live in one place.
//
// Encoders/decoders default to the shared `.iso8601` coders in `JSONCoding`;
// callers that need different behavior (custom key strategy, encryption of the
// serialized blob, a tolerant multi-strategy fallback) should keep their own
// bespoke logic rather than force it through here.

import Foundation

enum CodableDefaults {

    /// Loads and decodes a value for `key`, returning nil if absent or if
    /// decoding fails. Matches the existing stores' "best-effort load" policy.
    static func load<T: Decodable>(
        _ type: T.Type = T.self,
        forKey key: String,
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONCoding.iso8601Decoder
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Encodes and writes a value for `key`. Throws only if encoding fails.
    static func save<T: Encodable>(
        _ value: T,
        forKey key: String,
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONCoding.iso8601Encoder
    ) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }

    /// Removes the value stored for `key`.
    static func remove(forKey key: String, from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
