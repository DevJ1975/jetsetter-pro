// File: Core/Network/PercentEncoding.swift
//
// Shared percent-encoding primitives. Previously the path-segment and
// form-body encodings were copy-pasted across Endpoints (FlightAware /
// WorldTracer), CheckInService, and DisruptionResponseEngine — any change to
// the escaping rules had to be mirrored by hand. Centralized here so there's a
// single source of truth.

import Foundation

enum PercentEncoding {

    /// Percent-encodes a single URL path segment. Excludes "/" so a stray slash
    /// in the value can't inject an extra path component; also escapes spaces,
    /// "#", "%", and non-ASCII that would otherwise make `URL(string:)` fail.
    /// Returns nil only if the platform can't encode the value.
    static func pathSegment(_ value: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    /// Percent-encodes a value for an `application/x-www-form-urlencoded` body.
    /// `.urlQueryAllowed` still permits the sub-delimiters `+`, `&`, `=` (and
    /// `%`), so a value containing any of those would corrupt the body — exclude
    /// them. Falls back to the original value if encoding somehow fails.
    static func formValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
