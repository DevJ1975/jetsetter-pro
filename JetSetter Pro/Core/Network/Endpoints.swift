// File: Core/Network/Endpoints.swift

import Foundation

// MARK: - API Keys
// Values come from Info.plist via AppSecrets, sourced from Secrets.xcconfig.
// An empty string means the credential is not configured — callers should
// check AppSecrets.isConfigured(_:) before making live requests.

enum APIKeys {
    static var flightAware: String         { AppSecrets.value(for: .flightAware) ?? "" }
    static var billSpend: String           { AppSecrets.value(for: .billSpendToken) ?? "" }
}

// MARK: - Endpoints

/// Centralized URL builder for all Jetsetter API endpoints.
/// Add new endpoints here as new features are added.
nonisolated enum Endpoints {

    // MARK: - FlightAware AeroAPI

    enum FlightAware {
        private static let baseURL = "https://aeroapi.flightaware.com/aeroapi"

        /// Percent-encodes a single URL path segment. Excludes "/" so a stray
        /// slash in the value can't inject an extra path component; also escapes
        /// spaces, "#", "%", and non-ASCII that would otherwise make
        /// `URL(string:)` return nil.
        private static func encodedPathSegment(_ value: String) -> String? {
            PercentEncoding.pathSegment(value)
        }

        /// Returns the full URL for fetching flight status by flight identifier (e.g. "AA100")
        static func flightStatus(ident: String) -> URL? {
            guard let encoded = encodedPathSegment(ident) else { return nil }
            return URL(string: "\(baseURL)/flights/\(encoded)")
        }

        /// Returns the URL for the live position track of a flight. AeroAPI returns
        /// a `positions` array (lat/lon, altitude in 100s of ft, groundspeed kts,
        /// heading) for the flight identified by `ident` (flight number or faFlightId).
        static func flightTrack(ident: String) -> URL? {
            guard let encoded = encodedPathSegment(ident) else { return nil }
            return URL(string: "\(baseURL)/flights/\(encoded)/track")
        }

        /// Standard headers required for all FlightAware requests
        static var headers: [String: String] {
            ["x-apikey": APIKeys.flightAware]
        }
    }

    // MARK: - Open-Meteo
    // Free, no API key. Weather forecast + geocoding. All params are query items.

    enum OpenMeteo {
        private static let forecastBase  = "https://api.open-meteo.com/v1/forecast"
        private static let geocodingBase = "https://geocoding-api.open-meteo.com/v1/search"

        /// Current-conditions forecast for a single coordinate (temperature,
        /// weather code, wind), in Fahrenheit / km·h⁻¹.
        static func currentWeatherURL(latitude: Double, longitude: Double) -> URL? {
            var components = URLComponents(string: forecastBase)
            components?.queryItems = [
                URLQueryItem(name: "latitude",         value: String(latitude)),
                URLQueryItem(name: "longitude",        value: String(longitude)),
                URLQueryItem(name: "current",          value: "temperature_2m,weather_code,wind_speed_10m"),
                URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
                URLQueryItem(name: "wind_speed_unit",  value: "kmh"),
                URLQueryItem(name: "forecast_days",    value: "1")
            ]
            return components?.url
        }

        /// Multi-day daily forecast (high/low temp + weather code) for a coordinate.
        static func dailyForecastURL(latitude: Double, longitude: Double, days: Int) -> URL? {
            var components = URLComponents(string: forecastBase)
            components?.queryItems = [
                URLQueryItem(name: "latitude",         value: String(latitude)),
                URLQueryItem(name: "longitude",        value: String(longitude)),
                URLQueryItem(name: "daily",            value: "temperature_2m_max,temperature_2m_min,weather_code"),
                URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
                URLQueryItem(name: "forecast_days",    value: String(days)),
                URLQueryItem(name: "timezone",         value: "auto")
            ]
            return components?.url
        }

        /// Geocoding search for a place name, returning up to `count` candidates.
        static func geocodingURL(name: String, count: Int) -> URL? {
            var components = URLComponents(string: geocodingBase)
            components?.queryItems = [
                URLQueryItem(name: "name",     value: name),
                URLQueryItem(name: "count",    value: String(count)),
                URLQueryItem(name: "language", value: "en"),
                URLQueryItem(name: "format",   value: "json")
            ]
            return components?.url
        }
    }

    // MARK: - Open Exchange Rate API (open.er-api.com)
    // Free, no API key. Latest FX rates for a base currency.

    enum ExchangeRate {
        static func latestURL(base: String) -> URL? {
            URL(string: "https://open.er-api.com/v6/latest/\(base.uppercased())")
        }
    }
}
