// File: Core/Network/APIClient.swift

import Foundation

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL was invalid."
        case .notConfigured:
            return "This feature isn't configured — the required API credential is missing."
        case .unauthorized:
            return "Not authorized — check your API credentials."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited. Try again in about \(Int(retryAfter.rounded()))s."
            }
            return "Rate limited. Please try again shortly."
        case .requestFailed(let statusCode):
            return "Request failed with status code \(statusCode)."
        case .decodingFailed(let error):
            return "Failed to decode the response: \(error.localizedDescription)"
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}

// MARK: - Empty Response

/// Stand-in `Decodable` for endpoints that legitimately return no body
/// (HTTP 204, or a 200 with an empty payload — e.g. POST actions or token
/// revocation). Request `EmptyResponse` as the result type and `perform`
/// will short-circuit decoding instead of failing on an empty body.
struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

// MARK: - API Client

/// Shared HTTP client for all Jetsetter network requests.
/// All methods are async/await and throw typed APIErrors.
///
/// `@unchecked Sendable`: all stored state is immutable (`let`). `URLSession` is
/// Sendable; `JSONDecoder` is not marked Sendable but is only ever *read from*
/// here (`decode` mutates no instance state and is safe to call concurrently),
/// so sharing the one configured decoder across concurrent requests is sound.
/// This lets the shared singleton be used from any actor under Swift 6 / strict
/// concurrency without a data-race diagnostic.
final class APIClient: @unchecked Sendable {

    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Cached bare encoder for `post(...)` callers that don't pass one — avoids
    /// allocating a fresh `JSONEncoder` (an expensive Foundation object) per POST.
    /// Matches the previous default shape: camelCase keys, no date strategy.
    static let defaultEncoder = JSONEncoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        // FlightAware and most APIs return snake_case keys
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Parse ISO 8601 date strings automatically
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - GET Request

    /// Performs a GET request and decodes the JSON response into the specified type.
    func get<T: Decodable>(
        url: URL,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await perform(request: request)
    }

    // MARK: - POST Request

    /// Performs a POST request with a JSON body and decodes the JSON response.
    ///
    /// - Parameter encoder: The `JSONEncoder` used to serialize `body`. Defaults
    ///   to a bare encoder (camelCase keys, no special date handling) so callers
    ///   whose target API expects that shape — e.g. Google Vision's `maxResults`
    ///   — keep working. Services whose API expects snake_case keys or ISO-8601
    ///   dates should pass an encoder configured accordingly (see
    ///   `APIClient.snakeCaseEncoder`).
    func post<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        headers: [String: String] = [:],
        encoder: JSONEncoder = APIClient.defaultEncoder
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw APIError.unknown(error)
        }

        return try await perform(request: request)
    }

    /// A shared encoder matching the client's decoder conventions: snake_case
    /// keys and ISO-8601 dates. Use for APIs whose request bodies mirror the
    /// snake_case responses this client already decodes.
    static let snakeCaseEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: - Core Request Executor

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let body = try await data(for: request)

        // Empty-body fast path. A 204 No Content — or a 200 with an empty
        // payload, common for POST actions and token revocation — has no JSON to
        // decode. `data(for:)` returns empty `Data` for a 204 (it carries no
        // body), so an empty payload covers both cases. Return an `EmptyResponse`
        // without attempting a decode that would otherwise throw `decodingFailed`
        // on a request that actually succeeded.
        if let empty = EmptyResponse() as? T, body.isEmpty {
            return empty
        }

        do {
            return try decoder.decode(T.self, from: body)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    /// Executes a request through the shared policy — credential guard,
    /// transient-retry (idempotent GET only), and status-code → `APIError`
    /// mapping — and returns the raw response body without decoding.
    ///
    /// Prefer `get`/`post` for JSON. Reach for this when the caller owns body
    /// construction or response parsing: non-JSON bodies (multipart form-data,
    /// `application/x-www-form-urlencoded` token exchanges) or payloads the
    /// caller decodes itself. Routing these through here gives every write the
    /// same `.notConfigured` guard and typed error surface the GET paths get,
    /// instead of each call site hand-rolling `URLSession` status checks.
    func data(for request: URLRequest) async throws -> Data {
        // Fail fast on missing credentials. A blank credential header would
        // otherwise produce a live request that comes back as a confusing
        // 401/403; surfacing `.notConfigured` makes misconfiguration explicit.
        if Self.hasEmptyCredentialHeader(request) {
            throw APIError.notConfigured
        }

        // Only retry idempotent (GET) requests so a POST can't be double-submitted.
        let maxAttempts = (request.httpMethod ?? "GET") == "GET" ? 3 : 1
        var attempt = 0

        while true {
            attempt += 1
            let body: Data
            let response: URLResponse

            do {
                (body, response) = try await session.data(for: request)
            } catch {
                if attempt < maxAttempts, Self.isTransient(error) {
                    try await Self.backoff(attempt: attempt)
                    continue
                }
                throw APIError.unknown(error)
            }

            // Validate HTTP status code, retrying transient failures.
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                switch http.statusCode {
                case 401:
                    throw APIError.unauthorized
                case 429:
                    let retryAfter = Self.retryAfterSeconds(from: http)
                    if attempt < maxAttempts {
                        try await Self.backoff(attempt: attempt, suggested: retryAfter)
                        continue
                    }
                    throw APIError.rateLimited(retryAfter: retryAfter)
                case 500...599:
                    if attempt < maxAttempts {
                        try await Self.backoff(attempt: attempt)
                        continue
                    }
                    throw APIError.requestFailed(statusCode: http.statusCode)
                default:
                    // Everything else (incl. 404, which SITA WorldTracer matches on).
                    throw APIError.requestFailed(statusCode: http.statusCode)
                }
            }

            return body
        }
    }

    /// Header names that carry a credential across the app's endpoint groups.
    /// If any of these is present on the request but blank, the relevant API
    /// key/secret is unconfigured.
    private static let credentialHeaderNames: Set<String> = [
        "x-apikey", "x-api-key", "api-key", "x-partner-key",
        "x-goog-api-key", "authorization"
    ]

    /// True if the request carries a known credential header whose value is
    /// empty (or, for a Bearer/Token scheme, has no token after the scheme).
    private static func hasEmptyCredentialHeader(_ request: URLRequest) -> Bool {
        guard let headers = request.allHTTPHeaderFields else { return false }
        for (name, value) in headers where credentialHeaderNames.contains(name.lowercased()) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            // "Bearer" / "Token" with nothing after the scheme is also unconfigured.
            if parts.count == 2,
               ["bearer", "token"].contains(parts[0].lowercased()),
               parts[1].trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
            // EAN signature scheme (Expedia Rapid Lodging):
            //   "EAN APIKey=<key>,Signature=<sig>,timestamp=<ts>"
            // The value is never blank — it always carries a computed signature —
            // so the emptiness checks above cannot catch an unconfigured Expedia
            // credential. Inspect the APIKey field directly; a blank key is unconfigured.
            if parts.count == 2, parts[0].lowercased() == "ean",
               Self.eanAPIKeyIsBlank(parts[1]) {
                return true
            }
        }
        return false
    }

    /// True if the `APIKey=` field of an EAN `Authorization` value is missing or
    /// blank. `params` is the portion after the "EAN " scheme prefix, e.g.
    /// "APIKey=abc,Signature=…,timestamp=…".
    private static func eanAPIKeyIsBlank(_ params: Substring) -> Bool {
        for field in params.split(separator: ",") {
            let kv = field.split(separator: "=", maxSplits: 1)
            guard kv.first?.trimmingCharacters(in: .whitespaces).lowercased() == "apikey" else { continue }
            let value = kv.count == 2 ? kv[1].trimmingCharacters(in: .whitespaces) : ""
            return value.isEmpty
        }
        // No APIKey field at all → treat as unconfigured.
        return true
    }

    // MARK: - Retry helpers

    /// True for connectivity errors worth retrying.
    private static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .dnsLookupFailed, .notConnectedToInternet, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    /// RFC 1123 formatter for the HTTP-date form of `Retry-After`.
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    /// Parses the `Retry-After` header, which per RFC 7231 may be either a
    /// number of seconds or an HTTP-date. Returns the wait in seconds (>= 0).
    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(trimmed) {
            return max(seconds, 0)
        }
        if let date = httpDateFormatter.date(from: trimmed) {
            return max(date.timeIntervalSinceNow, 0)
        }
        return nil
    }

    /// Sleeps before the next attempt — honoring a server `Retry-After` when
    /// present, otherwise exponential backoff with jitter, capped so a stuck
    /// request can't hang the caller.
    private static func backoff(attempt: Int, suggested: TimeInterval? = nil) async throws {
        let delay: TimeInterval
        if let suggested {
            // Honor the server's wait exactly, bounded only by a generous ceiling
            // so a hostile/misconfigured value can't hang the request forever.
            delay = min(suggested, 60.0)
        } else {
            // Exponential backoff with jitter, capped so a stuck request can't hang.
            let base = min(pow(2.0, Double(attempt - 1)), 8.0)
            delay = min(base + Double.random(in: 0...0.3), 10.0)
        }
        try await Task.sleep(for: .seconds(delay))
    }
}
