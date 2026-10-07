// File: Core/Network/BackendError.swift
//
// Typed errors for the booking backend. The server answers every failure with
// `{"error": "<machine_code>", "message": "<sentence safe to show>"}` plus extra
// keys for specific codes (`fields` for validation_error, a fresh `offer` for
// price_changed). `BackendError.make` turns that body and the HTTP status into
// one case so a screen can branch on meaning instead of status codes:
//
//  * `priceChanged` carries the fresh offer so the app can show the new price
//    and ask the traveler to re-confirm instead of failing.
//  * `mayHaveCreatedBooking` marks the outcomes of a checkout where the request
//    might have reached the server anyway (timeout, dropped connection, 502).
//    The contract is explicit that a checkout is NEVER auto-retried; the app
//    fetches the booking list instead, so a second charge can't happen.

import Foundation

// MARK: - Error body

/// The JSON body of a non-2xx response. Every key is optional because a proxy,
/// a captive portal or an older server may answer with something else.
nonisolated struct BackendErrorBody: Decodable, Sendable, Equatable {
    var error: String?
    var message: String?
    /// field -> messages. The decoder's snake_case conversion also rewrites
    /// these dictionary keys ("given_name" arrives as "givenName"), so match
    /// them with `BackendError.fieldKey(_:)`.
    var fields: [String: [String]]?
    var offer: BackendOffer?

    private enum CodingKeys: String, CodingKey { case error, message, fields, offer }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error   = try? c.decodeIfPresent(String.self, forKey: .error)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        offer   = try? c.decodeIfPresent(BackendOffer.self, forKey: .offer)
        // DRF normally sends lists, but a single string per field is common too.
        if let lists = try? c.decodeIfPresent([String: [String]].self, forKey: .fields) {
            fields = lists
        } else if let singles = try? c.decodeIfPresent([String: String].self, forKey: .fields) {
            fields = singles.mapValues { [$0] }
        } else {
            fields = nil
        }
    }
}

// MARK: - Error

nonisolated enum BackendError: LocalizedError, Sendable, Equatable {
    /// `API_BACKEND_URL` is missing; the app uses the vendor hand-off instead.
    case notConfigured
    /// No connection, or data is off (airplane mode, roaming with data off).
    case offline
    case timedOut
    /// 401, after the one automatic re-registration already failed.
    case notAuthenticated
    case validation(message: String, fields: [String: [String]])
    case notFound(message: String)
    /// 409 price_changed. `offer` is the fresh offer when the server sent one.
    case priceChanged(message: String, offer: BackendOffer?)
    case offerExpired(message: String)
    /// 409 not_cancellable / invalid_state.
    case invalidState(code: String, message: String)
    case throttled(message: String, retryAfter: TimeInterval?)
    /// 502: Duffel or Stripe failed. Searches may be retried; checkouts must not.
    case upstream(message: String)
    /// 503: the server has no Duffel credentials.
    case flightsUnavailable(message: String)
    case server(status: Int, code: String?, message: String)
    /// A 2xx whose body wasn't the JSON we expected (a captive portal, a proxy).
    case invalidResponse
    case transport(String)

    // MARK: Building

    /// Maps an HTTP status and error body to a case.
    static func make(status: Int, body: Data, retryAfter: TimeInterval? = nil) -> BackendError {
        let parsed = try? BackendCoding.makeDecoder().decode(BackendErrorBody.self, from: body)
        let code = parsed?.error ?? ""
        let text = parsed?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = (text?.isEmpty == false) ? text : nil

        if status == 401 || code == "not_authenticated" { return .notAuthenticated }
        if code == "validation_error" || status == 400 {
            return .validation(message: message ?? "Please check the details and try again.",
                               fields: parsed?.fields ?? [:])
        }
        if code == "price_changed" {
            return .priceChanged(message: message ?? "The fare changed while you were booking.",
                                 offer: parsed?.offer)
        }
        if code == "offer_expired" {
            return .offerExpired(message: message ?? "This fare is no longer available.")
        }
        if code == "not_cancellable" || code == "invalid_state" {
            return .invalidState(code: code, message: message ?? "That isn't possible for this booking right now.")
        }
        if status == 429 || code == "throttled" {
            return .throttled(message: message ?? "Too many requests. Please wait a moment and try again.",
                              retryAfter: retryAfter)
        }
        if code == "flights_unavailable" || (status == 503 && code.isEmpty) {
            return .flightsUnavailable(message: message ?? "Flight booking isn't available right now.")
        }
        if status == 404 || code == "not_found" {
            return .notFound(message: message ?? "We couldn't find that.")
        }
        if code == "upstream_error" || status == 502 {
            return .upstream(message: message ?? "The airline booking service had a problem. Please try again in a moment.")
        }
        return .server(status: status, code: code.isEmpty ? nil : code,
                       message: message ?? "Something went wrong on our side.")
    }

    /// Maps a transport failure.
    static func make(urlError: URLError) -> BackendError {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .transport(urlError.localizedDescription)
        }
    }

    // MARK: Reading

    var errorDescription: String? { userMessage }

    /// A sentence that is safe to show the traveler.
    var userMessage: String {
        switch self {
        case .notConfigured:
            return "In-app booking isn't available in this build."
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .timedOut:
            return "The server took too long to answer. Check your connection and try again."
        case .notAuthenticated:
            return "We couldn't verify this device with the booking service. Please try again."
        case .validation(let message, _), .notFound(let message), .priceChanged(let message, _),
             .offerExpired(let message), .invalidState(_, let message), .throttled(let message, _),
             .upstream(let message), .flightsUnavailable(let message):
            return message
        case .server(_, _, let message):
            return message
        case .invalidResponse:
            return "The booking service sent an unexpected reply. If you're on hotel or airport Wi-Fi, finish signing in to it first."
        case .transport:
            return "We couldn't reach the booking service. Check your connection and try again."
        }
    }

    /// True when a checkout that failed this way may still have created a
    /// booking on the server. The app must look the booking up rather than retry.
    var mayHaveCreatedBooking: Bool {
        switch self {
        case .timedOut, .transport, .upstream, .invalidResponse: return true
        case .server(let status, _, _): return status >= 500
        default: return false
        }
    }

    /// True for connectivity failures, where cached data should be shown.
    var isConnectivity: Bool {
        switch self {
        case .offline, .timedOut, .transport: return true
        default: return false
        }
    }

    /// The server's per-field messages for a validation error, keyed by a
    /// normalised field name (see `fieldKey`).
    var fieldMessages: [String: [String]] {
        guard case .validation(_, let fields) = self else { return [:] }
        return Dictionary(fields.map { (Self.fieldKey($0.key), $0.value) }, uniquingKeysWith: +)
    }

    /// "given_name", "givenName" and "Given Name" all become "givenname", so a
    /// field error matches however the decoder rewrote the key.
    static func fieldKey(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
