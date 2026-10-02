// File: Core/Services/AppleIntelligenceStatus.swift
//
// Why Apple Intelligence can or can't run right now, in the app's own terms.
// A supported iPhone can still be without the model: the person turned Apple
// Intelligence off, or the model is still downloading after an update or a
// language change. Those need different words. "Not available" on a phone
// that will be ready in ten minutes makes people think the feature is broken;
// "Apple Intelligence is getting ready" tells them to come back.

import FoundationModels

nonisolated enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    /// This hardware can't run Apple Intelligence.
    case deviceNotEligible
    /// Supported, but switched off in Settings.
    case notEnabled
    /// Supported and on, but the model is still downloading or preparing.
    case gettingReady
    /// A reason added in a later OS that this build doesn't know.
    case unavailable

    /// The default on-device model's status right now.
    static var current: AppleIntelligenceStatus {
        status(for: SystemLanguageModel.default.availability)
    }

    static func status(for availability: SystemLanguageModel.Availability) -> AppleIntelligenceStatus {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:           return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady:               return .gettingReady
            @unknown default:                  return .unavailable
            }
        }
    }
}
