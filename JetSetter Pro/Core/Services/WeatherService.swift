// File: Core/Services/WeatherService.swift
//
// Weather for the app, WeatherKit first. WeatherKit is part of the Apple
// Developer Program (500,000 calls/month included) and needs the WeatherKit
// capability on the App ID plus the `com.apple.developer.weatherkit`
// entitlement (already in the entitlements file). Until that capability is
// enabled — or when WeatherKit is unavailable for a location — the service
// falls back to Open-Meteo (free, no key), so nothing in the app breaks.
//
// Apple requires attribution wherever WeatherKit data is shown; see
// `WeatherAttributionView`.

import Foundation
import CoreLocation
import WeatherKit

// MARK: - Weather Data

struct WeatherData {
    let temperatureFahrenheit: Double
    /// WMO weather code (native for Open-Meteo, mapped from WeatherKit's
    /// condition) so existing risk logic keeps working across both sources.
    let weatherCode: Int
    let windspeedKmh: Double
    let systemIcon: String
    let conditionDescription: String
    let source: WeatherSource

    /// One-clause description for on-device prompts.
    var summaryForPrompt: String {
        "\(conditionDescription.lowercased()), \(Int(temperatureFahrenheit.rounded()))°F"
    }
}

enum WeatherSource {
    case weatherKit
    case openMeteo
}

/// Multi-day summary used by the packing list.
struct DailyForecastSummary {
    let avgHighF: Double
    let avgLowF: Double
    let rainyDays: Int
    let snowyDays: Int
    let dominantCondition: String
    let source: WeatherSource
}

// MARK: - WMO Code Mapping

enum WMOWeatherCode {

    static func systemIcon(for code: Int) -> String {
        switch code {
        case 0:           return "sun.max.fill"
        case 1:           return "cloud.sun.fill"
        case 2:           return "cloud.fill"
        case 3:           return "smoke.fill"
        case 45, 48:      return "cloud.fog.fill"
        case 51, 53, 55:  return "cloud.drizzle.fill"
        case 56, 57:      return "cloud.sleet.fill"
        case 61, 63, 65:  return "cloud.rain.fill"
        case 66, 67:      return "cloud.sleet.fill"
        case 71, 73, 75:  return "cloud.snow.fill"
        case 77:          return "cloud.snow.fill"
        case 80, 81, 82:  return "cloud.heavyrain.fill"
        case 85, 86:      return "cloud.snow.fill"
        case 95:          return "cloud.bolt.fill"
        case 96, 99:      return "cloud.bolt.rain.fill"
        default:          return "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0:           return "Clear"
        case 1:           return "Mostly Clear"
        case 2:           return "Partly Cloudy"
        case 3:           return "Overcast"
        case 45, 48:      return "Foggy"
        case 51, 53, 55:  return "Drizzle"
        case 56, 57:      return "Freezing Drizzle"
        case 61, 63, 65:  return "Rain"
        case 66, 67:      return "Freezing Rain"
        case 71, 73, 75:  return "Snowfall"
        case 77:          return "Snow Grains"
        case 80, 81, 82:  return "Rain Showers"
        case 85, 86:      return "Snow Showers"
        case 95:          return "Thunderstorm"
        case 96, 99:      return "Heavy Thunderstorm"
        default:          return "Cloudy"
        }
    }

    /// Approximate WMO code for a WeatherKit condition, so `DepartureWeather.risk`
    /// and the packing forecast treat both sources alike.
    static func code(for condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot:                              return 0
        case .mostlyClear:                              return 1
        case .partlyCloudy:                             return 2
        case .cloudy, .mostlyCloudy, .haze, .smoky:     return 3
        case .foggy:                                    return 45
        case .drizzle:                                  return 51
        case .freezingDrizzle:                          return 56
        case .rain, .sunShowers:                        return 61
        case .heavyRain:                                return 65
        case .freezingRain:                             return 66
        case .flurries, .snow, .sunFlurries:            return 71
        case .heavySnow, .blizzard, .blowingSnow:       return 75
        case .sleet, .wintryMix:                        return 85
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .tropicalStorm, .hurricane: return 95
        case .strongStorms, .hail:                      return 96
        case .windy, .breezy, .blowingDust, .frigid:    return 3
        @unknown default:                               return 3
        }
    }
}

// MARK: - WeatherService

actor WeatherService {

    static let shared = WeatherService()

    private var cache: [String: (data: WeatherData, timestamp: Date)] = [:]
    private var dailyCache: [String: (data: DailyForecastSummary, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 600          // 10 minutes
    private let dailyCacheDuration: TimeInterval = 3_600   // 1 hour

    /// After any WeatherKit failure (most likely the capability isn't enabled on
    /// the App ID yet), skip WeatherKit for a while so weather still loads fast
    /// from the fallback instead of paying a failing round trip on every call.
    /// Retries after the window so enabling the capability needs no relaunch.
    private var weatherKitPausedUntil: Date = .distantPast
    private let weatherKitRetryInterval: TimeInterval = 30 * 60

    private var weatherKitDisabled: Bool { Date() < weatherKitPausedUntil }

    // MARK: - Current conditions

    /// Current conditions for the coordinates. Results are cached for 10 minutes.
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherData {
        let key = "\(Int((latitude * 10).rounded()))_\(Int((longitude * 10).rounded()))"
        if let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let result: WeatherData
        if let kit = await fetchFromWeatherKit(latitude: latitude, longitude: longitude) {
            result = kit
        } else {
            result = try await fetchFromOpenMeteo(latitude: latitude, longitude: longitude)
        }
        cache[key] = (data: result, timestamp: Date())
        return result
    }

    private func fetchFromWeatherKit(latitude: Double, longitude: Double) async -> WeatherData? {
        guard !weatherKitDisabled else { return nil }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let current = try await WeatherKit.WeatherService.shared.weather(for: location, including: .current)
            return WeatherData(
                temperatureFahrenheit: current.temperature.converted(to: .fahrenheit).value,
                weatherCode: WMOWeatherCode.code(for: current.condition),
                windspeedKmh: current.wind.speed.converted(to: .kilometersPerHour).value,
                systemIcon: current.symbolName + (current.symbolName.hasSuffix(".fill") ? "" : ".fill"),
                conditionDescription: current.condition.description,
                source: .weatherKit
            )
        } catch {
            noteWeatherKitFailure(error)
            return nil
        }
    }

    private func fetchFromOpenMeteo(latitude: Double, longitude: Double) async throws -> WeatherData {
        guard let url = Endpoints.OpenMeteo.currentWeatherURL(latitude: latitude, longitude: longitude) else {
            throw APIError.invalidURL
        }
        let response: OpenMeteoResponse = try await APIClient.shared.get(url: url)
        let code = response.current.weatherCode
        return WeatherData(
            temperatureFahrenheit: response.current.temperature2m,
            weatherCode: code,
            windspeedKmh: response.current.windSpeed10m,
            systemIcon: WMOWeatherCode.systemIcon(for: code),
            conditionDescription: WMOWeatherCode.description(for: code),
            source: .openMeteo
        )
    }

    // MARK: - Daily forecast

    /// High/low and precipitation summary for the next `days` days (1…10).
    func dailyForecast(latitude: Double, longitude: Double, days: Int) async throws -> DailyForecastSummary {
        let days = max(1, min(days, 10))
        let key = "\(Int((latitude * 10).rounded()))_\(Int((longitude * 10).rounded()))_\(days)"
        if let cached = dailyCache[key], Date().timeIntervalSince(cached.timestamp) < dailyCacheDuration {
            return cached.data
        }

        let result: DailyForecastSummary
        if let kit = await dailyFromWeatherKit(latitude: latitude, longitude: longitude, days: days) {
            result = kit
        } else {
            result = try await dailyFromOpenMeteo(latitude: latitude, longitude: longitude, days: days)
        }
        dailyCache[key] = (data: result, timestamp: Date())
        return result
    }

    private func dailyFromWeatherKit(latitude: Double, longitude: Double, days: Int) async -> DailyForecastSummary? {
        guard !weatherKitDisabled else { return nil }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let forecast = try await WeatherKit.WeatherService.shared.weather(for: location, including: .daily)
            let window = Array(forecast.prefix(days))
            guard !window.isEmpty else { return nil }
            let highs = window.map { $0.highTemperature.converted(to: .fahrenheit).value }
            let lows  = window.map { $0.lowTemperature.converted(to: .fahrenheit).value }
            let codes = window.map { WMOWeatherCode.code(for: $0.condition) }
            return Self.summary(highs: highs, lows: lows, codes: codes, source: .weatherKit)
        } catch {
            noteWeatherKitFailure(error)
            return nil
        }
    }

    private func dailyFromOpenMeteo(latitude: Double, longitude: Double, days: Int) async throws -> DailyForecastSummary {
        guard let url = Endpoints.OpenMeteo.dailyForecastURL(latitude: latitude, longitude: longitude, days: days) else {
            throw APIError.invalidURL
        }
        let response: OpenMeteoForecastResponse = try await APIClient.shared.get(url: url)
        let daily = response.daily
        return Self.summary(highs: daily.temperature2mMax, lows: daily.temperature2mMin, codes: daily.weatherCode, source: .openMeteo)
    }

    private static func summary(highs: [Double], lows: [Double], codes: [Int], source: WeatherSource) -> DailyForecastSummary {
        let avgHigh = highs.isEmpty ? 70 : highs.reduce(0, +) / Double(highs.count)
        let avgLow  = lows.isEmpty  ? 55 : lows.reduce(0, +)  / Double(lows.count)
        // WMO codes 61–67, 80–82 = rain; 71–77, 85–86 = snow; 95+ = storms (count as rain)
        let rainy = codes.filter { (61...67).contains($0) || (80...82).contains($0) || $0 >= 95 }.count
        let snowy = codes.filter { (71...77).contains($0) || (85...86).contains($0) }.count
        let dominant = codes.max { a, b in
            codes.filter { $0 == a }.count < codes.filter { $0 == b }.count
        }.map { WMOWeatherCode.description(for: $0) } ?? "Variable"
        return DailyForecastSummary(avgHighF: avgHigh, avgLowF: avgLow, rainyDays: rainy, snowyDays: snowy,
                                    dominantCondition: dominant, source: source)
    }

    // MARK: - Attribution

    /// Apple Weather attribution (mark images + legal page). Cached by WeatherKit.
    func attribution() async -> WeatherAttribution? {
        try? await WeatherKit.WeatherService.shared.attribution
    }

    /// True once any WeatherKit data has been served in this session — the UI
    /// shows the Apple Weather mark only when it's actually Apple's data.
    private(set) var hasServedWeatherKit = false

    private func noteWeatherKitFailure(_ error: Error) {
        weatherKitPausedUntil = Date().addingTimeInterval(weatherKitRetryInterval)
    }

    /// Records that WeatherKit data reached the UI (called from `fetch` paths).
    private func markServed() { hasServedWeatherKit = true }
}

// MARK: - Open-Meteo response models

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather

    struct CurrentWeather: Decodable {
        let temperature2m: Double
        let weatherCode: Int
        let windSpeed10m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode   = "weather_code"
            case windSpeed10m  = "wind_speed_10m"
        }
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let daily: Daily

    struct Daily: Decodable {
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case weatherCode      = "weather_code"
        }
    }
}
