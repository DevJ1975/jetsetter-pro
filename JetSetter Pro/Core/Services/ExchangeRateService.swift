// File: Core/Services/ExchangeRateService.swift
//
// Fetches live FX rates from open.er-api.com (free, no API key required).
// Daily refresh; cached snapshot survives offline use.

import Foundation

actor ExchangeRateService {

    static let shared = ExchangeRateService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

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
        let upper = base.uppercased()
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(upper)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(OpenERAPIResponse.self, from: data)
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
        return try? decoder.decode(ExchangeRates.self, from: data)
    }

    private func saveCache(_ rates: ExchangeRates, key: String) {
        guard let data = try? encoder.encode(rates) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Open ER-API Response

private struct OpenERAPIResponse: Decodable {
    let result: String
    let baseCode: String
    let rates: [String: Double]

    enum CodingKeys: String, CodingKey {
        case result
        case baseCode = "base_code"
        case rates
    }
}
