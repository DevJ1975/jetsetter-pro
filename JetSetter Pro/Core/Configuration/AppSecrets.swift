// File: Core/Configuration/AppSecrets.swift
//
// Central reader for all API credentials.
// Values are sourced from Info.plist keys, which are themselves populated
// from build settings (driven by Secrets.xcconfig). See SETUP.md.
//
// Any missing or placeholder value returns nil — callers must fall back
// gracefully (e.g. show mock data, skip a network call).

import Foundation

enum AppSecrets {

    enum Key: String {
        case flightAware           = "API_FLIGHTAWARE"
        case anthropic             = "API_ANTHROPIC"
        case expediaClientID       = "API_EXPEDIA_CLIENT_ID"
        case expediaClientSecret   = "API_EXPEDIA_CLIENT_SECRET"
        case uberServerToken       = "API_UBER_SERVER_TOKEN"
        case lyftClientID          = "API_LYFT_CLIENT_ID"
        case lyftClientSecret      = "API_LYFT_CLIENT_SECRET"
        case googleVision          = "API_GOOGLE_VISION"
        case sitaWorldTracer       = "API_SITA_WORLDTRACER"
        case enterprise            = "API_ENTERPRISE"
        case hertz                 = "API_HERTZ"
        case national              = "API_NATIONAL"
        case amadeusClientID       = "API_AMADEUS_CLIENT_ID"
        case amadeusClientSecret   = "API_AMADEUS_CLIENT_SECRET"
        case duffel                = "API_DUFFEL"
        // Duffel proxy (token stays server-side — see server/duffel-proxy)
        case duffelProxyURL        = "API_DUFFEL_PROXY_URL"
        case duffelProxyKey        = "API_DUFFEL_PROXY_KEY"
        // Supabase backend (shared cross-platform data + auth)
        case supabaseURL           = "API_SUPABASE_URL"
        case supabaseAnonKey       = "API_SUPABASE_ANON_KEY"
        // Claude proxy (Anthropic key stays server-side — see supabase/functions/claude-proxy)
        case claudeProxyURL        = "API_CLAUDE_PROXY_URL"
        // Expense providers (OAuth)
        case expensifyPartnerKey   = "API_EXPENSIFY_PARTNER_KEY"
        case rampClientID          = "API_RAMP_CLIENT_ID"
        case rampClientSecret      = "API_RAMP_CLIENT_SECRET"
        case brexClientID          = "API_BREX_CLIENT_ID"
        case divvyClientID         = "API_DIVVY_CLIENT_ID"
    }

    /// Returns the configured value for `key`, or `nil` when unset/placeholder.
    static func value(for key: Key) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key.rawValue) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("YOUR_") || trimmed == "REPLACE_ME" { return nil }
        return trimmed
    }

    /// True when a credential exists for the given key. Used by call sites
    /// to decide between live network calls and mock fallbacks.
    static func isConfigured(_ key: Key) -> Bool {
        value(for: key) != nil
    }
}
