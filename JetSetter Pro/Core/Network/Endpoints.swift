// File: Core/Network/Endpoints.swift

import Foundation

// MARK: - API Keys
// Values come from Info.plist via AppSecrets, sourced from Secrets.xcconfig.
// An empty string means the credential is not configured — callers should
// check AppSecrets.isConfigured(_:) before making live requests.

enum APIKeys {
    static var flightAware: String         { AppSecrets.value(for: .flightAware) ?? "" }
    static var claude: String              { AppSecrets.value(for: .anthropic) ?? "" }
    // Expedia (EAN) credentials moved server-side — the signed auth header is
    // fetched from the proxy by ExpediaAuthService, so no key/secret here.
    static var uberServerToken: String     { AppSecrets.value(for: .uberServerToken) ?? "" }
    static var uberClientID: String        { AppSecrets.value(for: .uberClientID) ?? "" }
    static var uberClientSecret: String    { AppSecrets.value(for: .uberClientSecret) ?? "" }
    static var lyftClientID: String        { AppSecrets.value(for: .lyftClientID) ?? "" }
    static var lyftClientSecret: String    { AppSecrets.value(for: .lyftClientSecret) ?? "" }
    static var googleVision: String        { AppSecrets.value(for: .googleVision) ?? "" }
    static var sitaWorldTracer: String     { AppSecrets.value(for: .sitaWorldTracer) ?? "" }
    static var enterprise: String          { AppSecrets.value(for: .enterprise) ?? "" }
    static var hertz: String               { AppSecrets.value(for: .hertz) ?? "" }
    static var national: String            { AppSecrets.value(for: .national) ?? "" }
    static var billSpend: String           { AppSecrets.value(for: .billSpendToken) ?? "" }
}

// MARK: - Endpoints

/// Centralized URL builder for all Jetsetter API endpoints.
/// Add new endpoints here as new features are added.
enum Endpoints {

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

    // MARK: - Anthropic Claude API

    enum Claude {
        private static let baseURL = "https://api.anthropic.com/v1"

        /// URL for the Claude messages endpoint
        static var messagesURL: URL? {
            URL(string: "\(baseURL)/messages")
        }

        /// Standard headers required for all Claude requests
        static var headers: [String: String] {
            [
                "x-api-key": APIKeys.claude,
                "anthropic-version": "2023-06-01"
            ]
        }
    }

    // MARK: - Expedia Partner Solutions (Rapid API)
    // Rapid Lodging (availability/content/booking) is served from the EAN hosts
    // and authenticated with EAN signature auth (see ExpediaAuthService), NOT
    // OAuth2 — only a subset of Rapid APIs (Typeahead, Geography, Cars) use
    // OAuth2. The prior `api.expediagroup.com` host + OAuth2 Bearer combination
    // returned request_unauthenticated for availability.

    enum Expedia {
        // Sandbox in Debug, production in Release/TestFlight. Requires
        // production Expedia credentials in Secrets.xcconfig.
        #if DEBUG
        private static let baseURL = "https://test.ean.com"
        #else
        private static let baseURL = "https://api.ean.com"
        #endif

        /// Hotel property availability search (Rapid Lodging v3)
        static var propertyAvailabilityURL: URL? {
            URL(string: "\(baseURL)/v3/properties/availability")
        }

        /// Region search (Rapid Geography v3). Resolves free-text destination
        /// input (e.g. "Tokyo") to Expedia `region_id`s that the availability
        /// search actually understands. `q` is the typeahead query; requesting
        /// `include=standard` returns each region's `id` in the response.
        static func regionSearchURL(query: String) -> URL? {
            var components = URLComponents(string: "\(baseURL)/v3/regions")
            components?.queryItems = [
                URLQueryItem(name: "q",        value: query),
                URLQueryItem(name: "include",  value: "standard"),
                URLQueryItem(name: "language", value: "en-US"),
                URLQueryItem(name: "limit",    value: "1")
            ]
            return components?.url
        }
    }

    // MARK: - Uber API
    // Uber retired anonymous server tokens; app-level requests now mint a Bearer
    // token via the OAuth2 client-credentials grant (scope `ride_request.estimate`).

    enum Uber {
        private static let baseURL = "https://api.uber.com/v1.2"

        /// OAuth2 client-credentials token endpoint.
        static var tokenURL: URL? {
            URL(string: "https://auth.uber.com/oauth/v2/token")
        }

        /// Scope required for anonymous price estimates.
        static let estimateScope = "ride_request.estimate"

        /// Price estimates for a given route.
        static func priceEstimatesURL(
            startLatitude: Double, startLongitude: Double,
            endLatitude: Double, endLongitude: Double
        ) -> URL? {
            var components = URLComponents(string: "\(baseURL)/estimates/price")
            components?.queryItems = [
                URLQueryItem(name: "start_latitude",  value: String(startLatitude)),
                URLQueryItem(name: "start_longitude", value: String(startLongitude)),
                URLQueryItem(name: "end_latitude",    value: String(endLatitude)),
                URLQueryItem(name: "end_longitude",   value: String(endLongitude))
            ]
            return components?.url
        }

        static func headers(token: String) -> [String: String] {
            ["Authorization": "Bearer \(token)"]
        }
    }

    // MARK: - Lyft API
    // NOTE: Lyft discontinued its public consumer ride-estimate API and SDKs.
    // Only the separate, contract-gated Lyft Business API remains. The estimate
    // path below is retained for reference but is not called at runtime — the
    // app deep-links to ride.lyft.com for booking instead. See
    // GroundTransportViewModel.fetchLyftEstimates.

    enum Lyft {
        private static let baseURL = "https://api.lyft.com/v1"

        /// OAuth 2.0 token endpoint for client credentials
        static var tokenURL: URL? {
            URL(string: "https://api.lyft.com/oauth/token")
        }

        /// Cost estimates for a given route
        static func costEstimatesURL(
            startLatitude: Double, startLongitude: Double,
            endLatitude: Double, endLongitude: Double
        ) -> URL? {
            var components = URLComponents(string: "\(baseURL)/cost")
            components?.queryItems = [
                URLQueryItem(name: "start_lat", value: String(startLatitude)),
                URLQueryItem(name: "start_lng", value: String(startLongitude)),
                URLQueryItem(name: "end_lat",   value: String(endLatitude)),
                URLQueryItem(name: "end_lng",   value: String(endLongitude))
            ]
            return components?.url
        }

        static func headers(token: String) -> [String: String] {
            ["Authorization": "Bearer \(token)"]
        }
    }

    // MARK: - Google Vision API

    enum GoogleVision {
        /// Annotate endpoint. The API key is sent in the X-Goog-Api-Key header
        /// (see `headers`) rather than a `?key=` query param, so it can't
        /// leak into request logs, proxy caches, or crash/analytics URLs.
        static var annotateURL: URL? {
            URL(string: "https://vision.googleapis.com/v1/images:annotate")
        }

        /// Auth header carrying the Google Vision API key.
        static var headers: [String: String] {
            ["X-Goog-Api-Key": APIKeys.googleVision]
        }
    }

    // MARK: - SITA WorldTracer

    enum WorldTracer {
        private static let baseURL = "https://api.sita.aero/baggage/v1"

        /// Returns the URL to look up a bag by its 10-digit airline baggage tag number
        static func baggageURL(tagNumber: String) -> URL? {
            guard let encoded = PercentEncoding.pathSegment(tagNumber) else { return nil }
            return URL(string: "\(baseURL)/baggage/\(encoded)")
        }

        static var headers: [String: String] {
            ["x-partner-key": APIKeys.sitaWorldTracer]
        }
    }

    // MARK: - Find My Deep Link

    enum FindMy {
        /// Opens the Apple Find My app. Falls back to App Store if not available.
        static let appURL = URL(string: "findmy://")
        static let appStoreURL = URL(string: "https://apps.apple.com/app/find-my/id1514844621")
    }

    // MARK: - Enterprise Rent-A-Car
    // NOTE: Enterprise's public API requires a corporate account + partner key.
    // We use deep links for booking and a placeholder search endpoint.

    enum Enterprise {
        private static let baseURL = "https://api.enterprise.com/v1"

        /// Search for available vehicles at a given location
        static func searchURL(pickupLocationCode: String, dropoffLocationCode: String,
                              pickupDate: String, dropoffDate: String) -> URL? {
            var components = URLComponents(string: "\(baseURL)/vehicles/availability")
            components?.queryItems = [
                URLQueryItem(name: "pickup_location", value: pickupLocationCode),
                URLQueryItem(name: "dropoff_location", value: dropoffLocationCode),
                URLQueryItem(name: "pickup_date_time", value: pickupDate),
                URLQueryItem(name: "dropoff_date_time", value: dropoffDate)
            ]
            return components?.url
        }

        static var headers: [String: String] {
            ["x-api-key": APIKeys.enterprise]
        }

        /// Deep link to open the Enterprise iOS app to a specific location search
        static let appScheme = "enterprise://"
        static let appStoreURL = URL(string: "https://apps.apple.com/app/enterprise-rent-a-car/id1492681603")
    }

    // MARK: - Hertz

    enum Hertz {
        private static let baseURL = "https://api.hertz.com/v1"

        static func searchURL(pickupLocation: String, dropoffLocation: String,
                              pickupDate: String, dropoffDate: String) -> URL? {
            var components = URLComponents(string: "\(baseURL)/reservation/availability")
            components?.queryItems = [
                URLQueryItem(name: "pickup_location_id", value: pickupLocation),
                URLQueryItem(name: "return_location_id", value: dropoffLocation),
                URLQueryItem(name: "pickup_date", value: pickupDate),
                URLQueryItem(name: "return_date", value: dropoffDate)
            ]
            return components?.url
        }

        static var headers: [String: String] {
            ["api-key": APIKeys.hertz]
        }

        static let appScheme = "hertz://"
        static let appStoreURL = URL(string: "https://apps.apple.com/app/hertz/id545396978")
    }

    // MARK: - National Car Rental

    enum National {
        private static let baseURL = "https://api.nationalcar.com/v1"

        static func searchURL(pickupLocation: String, dropoffLocation: String,
                              pickupDate: String, dropoffDate: String) -> URL? {
            var components = URLComponents(string: "\(baseURL)/vehicles/search")
            components?.queryItems = [
                URLQueryItem(name: "pickup_location", value: pickupLocation),
                URLQueryItem(name: "return_location", value: dropoffLocation),
                URLQueryItem(name: "pickup_date", value: pickupDate),
                URLQueryItem(name: "return_date", value: dropoffDate)
            ]
            return components?.url
        }

        static var headers: [String: String] {
            ["x-api-key": APIKeys.national]
        }

        static let appScheme = "nationalcar://"
        static let appStoreURL = URL(string: "https://apps.apple.com/app/national-car-rental/id543089631")
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
