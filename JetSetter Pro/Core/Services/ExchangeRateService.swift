// File: Core/Services/ExchangeRateService.swift
//
// Fetches live FX rates from open.er-api.com (free, no API key required).
// Daily refresh; cached snapshot survives offline use.

import Foundation

actor ExchangeRateService {

    static let shared = ExchangeRateService()
    private init() {}

    /// Returns the latest rates for `base` currency. Cache is preferred when
    /// fresh (<6h); falls back to cache when the network call fails so the
    /// converter keeps working offline.
    func rates(for base: String) async -> ExchangeRates? {
        let key = cacheKey(for: base)

        if let cached = loadCache(key: key), cached.isFresh {
            return cached
        }

        if let live = try? await fetchLive(base: base) {
            saveCache(live, key: key)
            return live
        }

        // Live fetch failed — return stale cache if we have one.
        return loadCache(key: key)
    }

    // MARK: - Networking

    private func fetchLive(base: String) async throws -> ExchangeRates {
        guard let url = Endpoints.ExchangeRate.latestURL(base: base) else {
            throw APIError.invalidURL
        }

        // Routed through the shared APIClient (typed errors, transient retry).
        // `OpenERAPIResponse`'s explicit CodingKeys take precedence over the
        // client decoder's `.convertFromSnakeCase`; there are no Date fields so
        // the `.iso8601` strategy is a no-op here. The application-level
        // `result == "success"` guard is preserved below.
        let decoded: OpenERAPIResponse = try await APIClient.shared.get(url: url)
        guard decoded.result == "success" else {
            throw URLError(.cannotParseResponse)
        }

        return ExchangeRates(
            base: decoded.baseCode,
            rates: decoded.rates,
            fetchedAt: Date()
        )
    }

    // MARK: - Cache

    private func cacheKey(for base: String) -> String {
        "exchange_rates_\(base.uppercased())"
    }

    private func loadCache(key: String) -> ExchangeRates? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONCoding.iso8601Decoder.decode(ExchangeRates.self, from: data)
    }

    private func saveCache(_ rates: ExchangeRates, key: String) {
        guard let data = try? JSONCoding.iso8601Encoder.encode(rates) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Open ER-API Response

private nonisolated struct OpenERAPIResponse: Decodable {
    let result: String
    let baseCode: String
    let rates: [String: Double]

    enum CodingKeys: String, CodingKey {
        case result
        case baseCode = "base_code"
        case rates
    }
}
