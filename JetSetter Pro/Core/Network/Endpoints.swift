// File: Core/Network/Endpoints.swift

import Foundation

// MARK: - API Keys
// Values come from Info.plist via AppSecrets, sourced from Secrets.xcconfig.
// An empty string means the credential is not configured — callers should
// check AppSecrets.isConfigured(_:) before making live requests.

enum APIKeys {
    static var flightAware: String         { AppSecrets.value(for: .flightAware) ?? "" }
    static var claude: String              { AppSecrets.value(for: .anthropic) ?? "" }
    static var expediaClientID: String     { AppSecrets.value(for: .expediaClientID) ?? "" }
    static var expediaClientSecret: String { AppSecrets.value(for: .expediaClientSecret) ?? "" }
    static var uberServerToken: String     { AppSecrets.value(for: .uberServerToken) ?? "" }
    static var lyftClientID: String        { AppSecrets.value(for: .lyftClientID) ?? "" }
    static var lyftClientSecret: String    { AppSecrets.value(for: .lyftClientSecret) ?? "" }
    static var googleVision: String        { AppSecrets.value(for: .googleVision) ?? "" }
    static var sitaWorldTracer: String     { AppSecrets.value(for: .sitaWorldTracer) ?? "" }
    static var enterpriseApiKey: String    { AppSecrets.value(for: .enterprise) ?? "" }
    static var hertzApiKey: String         { AppSecrets.value(for: .hertz) ?? "" }
    static var nationalApiKey: String      { AppSecrets.value(for: .national) ?? "" }
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
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove("/")
            return value.addingPercentEncoding(withAllowedCharacters: allowed)
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

    enum Expedia {
        // Sandbox data API in Debug, production in Release/TestFlight. Auth is
        // always production. Requires production Expedia credentials in Secrets.xcconfig.
        #if DEBUG
        private static let baseURL = "https://test.api.expediagroup.com"
        #else
        private static let baseURL = "https://api.expediagroup.com"
        #endif
        private static let authBaseURL = "https://api.expediagroup.com"

        /// OAuth 2.0 token endpoint — exchanges client credentials for a Bearer token
        static var tokenURL: URL? {
            URL(string: "\(authBaseURL)/identity/oauth2/v3/token")
        }

        /// Hotel property availability search
        static var propertyAvailabilityURL: URL? {
            URL(string: "\(baseURL)/v3/properties/availability")
        }

        /// Returns Bearer auth header using the provided token
        static func bearerHeaders(token: String) -> [String: String] {
            ["Authorization": "Bearer \(token)"]
        }
    }

    // MARK: - Uber API

    enum Uber {
        private static let baseURL = "https://api.uber.com/v1.2"

        /// Price estimates for a given route — uses server token, no user login required
        static func priceEstimatesURL(
            startLatitude: Double, startLongitude: Double,
            endLatitude: Double, endLongitude: Double
        ) -> URL? {
            var components = URLComponents(string: "\(baseURL)/estimates/price")
            components?.queryItems = [
                URLQueryItem(name: "start_latitude",  value: "\(startLatitude)"),
                URLQueryItem(name: "start_longitude", value: "\(startLongitude)"),
                URLQueryItem(name: "end_latitude",    value: "\(endLatitude)"),
                URLQueryItem(name: "end_longitude",   value: "\(endLongitude)")
            ]
            return components?.url
        }

        static var headers: [String: String] {
            ["Authorization": "Token \(APIKeys.uberServerToken)"]
        }
    }

    // MARK: - Lyft API

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
                URLQueryItem(name: "start_lat", value: "\(startLatitude)"),
                URLQueryItem(name: "start_lng", value: "\(startLongitude)"),
                URLQueryItem(name: "end_lat",   value: "\(endLatitude)"),
                URLQueryItem(name: "end_lng",   value: "\(endLongitude)")
            ]
            return components?.url
        }

        static func bearerHeaders(token: String) -> [String: String] {
            ["Authorization": "Bearer \(token)"]
        }
    }

    // MARK: - Google Vision API

    enum GoogleVision {
        /// Annotate endpoint. The API key is sent in the X-Goog-Api-Key header
        /// (see `authHeaders`) rather than a `?key=` query param, so it can't
        /// leak into request logs, proxy caches, or crash/analytics URLs.
        static var annotateURL: URL? {
            URL(string: "https://vision.googleapis.com/v1/images:annotate")
        }

        /// Auth header carrying the Google Vision API key.
        static var authHeaders: [String: String] {
            ["X-Goog-Api-Key": APIKeys.googleVision]
        }
    }

    // MARK: - SITA WorldTracer

    enum WorldTracer {
        private static let baseURL = "https://api.sita.aero/baggage/v1"

        /// Returns the URL to look up a bag by its 10-digit airline baggage tag number
        static func baggageURL(tagNumber: String) -> URL? {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove("/")
            guard let encoded = tagNumber.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return nil
            }
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
            ["x-api-key": APIKeys.enterpriseApiKey]
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
            ["api-key": APIKeys.hertzApiKey]
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
            ["x-api-key": APIKeys.nationalApiKey]
        }

        static let appScheme = "nationalcar://"
        static let appStoreURL = URL(string: "https://apps.apple.com/app/national-car-rental/id543089631")
    }
}
