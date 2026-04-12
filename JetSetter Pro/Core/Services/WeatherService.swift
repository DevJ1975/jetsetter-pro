// File: Core/Services/WeatherService.swift
// Fetches current weather via Open-Meteo (free, no API key required).

import Foundation

// MARK: - Weather Data

struct WeatherData {
    let temperatureFahrenheit: Double
    let weatherCode: Int
    let windspeedKmh: Double

    var systemIcon: String        { WMOWeatherCode.systemIcon(for: weatherCode) }
    var conditionDescription: String { WMOWeatherCode.description(for: weatherCode) }
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
}

// MARK: - WeatherService

actor WeatherService {

    static let shared = WeatherService()

    private var cache: [String: (data: WeatherData, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 600  // 10 minutes

    /// Fetches weather for the given coordinates. Results are cached for 10 minutes.
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherData {
        let key = "\(Int(latitude * 10))_\(Int(longitude * 10))"

        if let cached = cache[key], Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.data
        }

        let urlString = [
            "https://api.open-meteo.com/v1/forecast",
            "?latitude=\(latitude)&longitude=\(longitude)",
            "&current=temperature_2m,weather_code,wind_speed_10m",
            "&temperature_unit=fahrenheit&wind_speed_unit=kmh&forecast_days=1"
        ].joined()

        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        let result = WeatherData(
            temperatureFahrenheit: response.current.temperature2m,
            weatherCode:           response.current.weatherCode,
            windspeedKmh:          response.current.windSpeed10m
        )

        cache[key] = (data: result, timestamp: Date())
        return result
    }
}

// MARK: - Response Models

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
