// File: Core/Services/IRIS/IRISAgentService.swift
//
// IRIS sits one layer above AIService. She composes Instructions + her tool
// catalog (added in Phase 2) into a single LanguageModelSession, streams
// responses, and exposes a simple chat API to the view layer.

import Foundation
import FoundationModels

@MainActor
final class IRISAgentService {

    static let shared = IRISAgentService()

    /// Cached on-device session. We recreate when instructions change or the
    /// transcript needs to be cleared.
    private var session: LanguageModelSession?
    private var sessionInstructions: String = ""

    /// True when IRIS can run on this device (Apple Intelligence available).
    var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default:         return false
        }
    }

    var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence, which powers IRIS."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence isn't enabled. Turn it on in Settings to chat with IRIS."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable:
            return "IRIS is temporarily unavailable on this device."
        }
    }

    private init() {}

    // MARK: - Chat API

    /// Streams a response from IRIS. Each yielded String is the cumulative
    /// content so far; the view layer should overwrite its buffer with each.
    func streamResponse(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard self.isAvailable else {
                    continuation.finish(throwing: IRISError.unavailable)
                    return
                }
                let session = self.activeSession()
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    // Context overflow → reset session for next request
                    self.session = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Begins a fresh conversation (clears transcript). Memory persists.
    func resetConversation() {
        session = nil
        sessionInstructions = ""
    }

    // MARK: - Session lifecycle

    private func activeSession() -> LanguageModelSession {
        let currentInstructions = IRISPersonality.instructionsForCurrentUser()
        if let existing = session, sessionInstructions == currentInstructions {
            return existing
        }
        let newSession = LanguageModelSession(
            tools: IRISAgentService.tools,
            instructions: currentInstructions
        )
        session = newSession
        sessionInstructions = currentInstructions
        return newSession
    }

    /// The five tools IRIS can call. Defined as a static so the array is built
    /// once and shared across sessions.
    private static let tools: [any Tool] = [
        GetTripsTool(),
        GetWeatherTool(),
        GetVisaAndEssentialsTool(),
        RememberPreferenceTool(),
        GetDepartureRecommendationTool()
    ]
}

// MARK: - Errors

enum IRISError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "IRIS is unavailable on this device."
        }
    }
}
