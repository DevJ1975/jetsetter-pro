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
                // DEMO PATH: when running in demo mode and Apple Intelligence
                // isn't available (or to guarantee a great demo answer),
                // stream a curated IRIS-voice canned response.
                if !self.isAvailable && MockDataService.isEnabled {
                    await self.streamDemoResponse(prompt: prompt, into: continuation)
                    return
                }

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
                    // On any failure in demo mode, fall back to canned response.
                    if MockDataService.isEnabled {
                        await self.streamDemoResponse(prompt: prompt, into: continuation)
                        return
                    }
                    // Context overflow → reset session for next request
                    self.session = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Drips a canned response character-by-character so it feels like Apple
    /// Intelligence is generating it live.
    private func streamDemoResponse(
        prompt: String,
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        // Brief "thinking" pause for realism.
        try? await Task.sleep(for: .milliseconds(400))
        let reply = IRISDemoResponses.response(for: prompt)
        var cumulative = ""
        for char in reply {
            cumulative.append(char)
            continuation.yield(cumulative)
            try? await Task.sleep(for: .milliseconds(11))
        }
        continuation.finish()
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

    /// The six tools IRIS can call. Defined as a static so the array is built
    /// once and shared across sessions.
    private static let tools: [any Tool] = [
        GetTripsTool(),
        GetWeatherTool(),
        GetVisaAndEssentialsTool(),
        RememberPreferenceTool(),
        GetDepartureRecommendationTool(),
        SubmitExpensesTool()
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
