// File: Core/Utilities/AuthValidation.swift
//
// Client-side email/password validation for the Supabase account form. Runs
// before any network call so malformed input never reaches GoTrue and the user
// gets an immediate, specific message. Sign-up enforces a password policy;
// sign-in only checks structural validity (existing accounts may predate the
// policy, so we must not lock them out).

import Foundation

enum AuthValidation {

    /// Minimum password length enforced at sign-up.
    static let minPasswordLength = 8

    enum Failure: LocalizedError {
        case invalidEmail
        case emptyPassword
        case passwordTooShort(min: Int)
        case passwordTooWeak

        var errorDescription: String? {
            switch self {
            case .invalidEmail:            return "Enter a valid email address."
            case .emptyPassword:           return "Enter your password."
            case .passwordTooShort(let m): return "Password must be at least \(m) characters."
            case .passwordTooWeak:         return "Password must include at least one letter and one number."
            }
        }
    }

    /// Validates input for creating a new account. Returns the first failure, or
    /// nil when the input is acceptable.
    static func signUpFailure(email: String, password: String) -> Failure? {
        if !isValidEmail(email) { return .invalidEmail }
        if password.count < minPasswordLength { return .passwordTooShort(min: minPasswordLength) }
        let hasLetter = password.contains { $0.isLetter }
        let hasDigit  = password.contains { $0.isNumber }
        if !(hasLetter && hasDigit) { return .passwordTooWeak }
        return nil
    }

    /// Validates input for signing in to an existing account. Only structural
    /// checks — no complexity policy, to avoid rejecting valid legacy passwords.
    static func signInFailure(email: String, password: String) -> Failure? {
        if !isValidEmail(email) { return .invalidEmail }
        if password.isEmpty { return .emptyPassword }
        return nil
    }

    /// Lightweight RFC-5322-ish structural check. Not a deliverability guarantee
    /// (that's the confirmation email's job) — just enough to catch typos.
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
