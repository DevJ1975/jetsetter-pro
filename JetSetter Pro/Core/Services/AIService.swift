// File: Core/Services/AIService.swift
//
// On-device text generation for one-shot, free-text tasks (today: the traveler
// persona in TravelProfileStore). Actions are Siri App Intents; this service is
// only for prompts that need free text.
//
// There is deliberately no cloud fallback. JetSetter Pro runs with no backend:
// when Apple Intelligence is unavailable the caller gets `AIError.unavailable`
// and keeps whatever it already had.
//
// All paths emit cumulative response snapshots so the view layer can simply
// assign each value to its `streamingContent` state without tracking deltas.

import Foundation
import FoundationModels

// MARK: - History Entry

struct AIChatTurn: Sendable {
    let role: String   // "user" or "assistant"
    let content: String
}

// MARK: - Errors

enum AIError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence isn't available on this device."
        }
    }
}

// MARK: - AIService

@MainActor
final class AIService {

    static let shared = AIService()
    private init() {}

    /// Cached on-device session. We recreate it lazily when missing or when the
    /// transcript grows past the 4096-token context window.
    // Stored as `Any?` so this property exists on the iOS 18 deployment target;
    // the concrete iOS 26-only `LanguageModelSession` is only named inside
    // `@available` contexts below.
    private var appleSession: Any?
    private var appleSessionInstructions: String = ""

    /// True when the on-device model can generate right now.
    var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }

    var providerStatusLabel: String {
        isAvailable ? "Powered by Apple Intelligence" : "AI unavailable"
    }

    // MARK: - Streaming entry point

    /// Streams an on-device response. Each yielded String is the *cumulative*
    /// content generated so far; callers should overwrite their UI buffer with
    /// each value. Finishes with `AIError.unavailable` when Apple Intelligence
    /// can't run on this device.
    func streamResponse(
        prompt: String,
        history: [AIChatTurn],
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        if #available(iOS 26.0, *), isAvailable {
            return streamFromAppleIntelligence(
                prompt: prompt,
                history: history,
                systemPrompt: systemPrompt
            )
        }
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIError.unavailable)
        }
    }

    // MARK: - Apple Intelligence

    @available(iOS 26.0, *)
    private func streamFromAppleIntelligence(
        prompt: String,
        history: [AIChatTurn],
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                // A cached session maintains its own transcript across requests, so
                // for a warm session we send only the new user message. When the
                // session has to be (re)created — first turn, changed system prompt,
                // or after a context-window reset — it is seeded by replaying
                // `history` so prior turns survive.
                let session = self.sessionForAppleIntelligence(
                    systemPrompt: systemPrompt,
                    history: history
                )
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    // Context window exceeded → drop the session and transparently
                    // retry once against a fresh one in the same request, so the
                    // user doesn't have to manually resend. Propagate other errors.
                    self.appleSession = nil
                    if case .exceededContextWindowSize = error {
                        do {
                            let retrySession = self.sessionForAppleIntelligence(
                                systemPrompt: systemPrompt,
                                history: history
                            )
                            let retryStream = retrySession.streamResponse(to: prompt)
                            for try await snapshot in retryStream {
                                continuation.yield(snapshot.content)
                            }
                            continuation.finish()
                        } catch {
                            self.appleSession = nil
                            continuation.finish(throwing: error)
                        }
                    } else {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    // Non-generation errors (e.g. cancellation) → drop the session
                    // so the next request gets a fresh one, then propagate.
                    self.appleSession = nil
                    continuation.finish(throwing: error)
                }
            }
            // Stop the on-device model when the consumer stops listening.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @available(iOS 26.0, *)
    private func sessionForAppleIntelligence(
        systemPrompt: String,
        history: [AIChatTurn]
    ) -> LanguageModelSession {
        if let existing = appleSession as? LanguageModelSession, appleSessionInstructions == systemPrompt {
            return existing
        }
        // Rehydrate from a transcript so prior turns aren't lost on (re)creation.
        // When there's no history, fall back to the plain instructions initializer.
        let session: LanguageModelSession
        if history.isEmpty {
            session = LanguageModelSession(instructions: systemPrompt)
        } else {
            session = LanguageModelSession(
                transcript: Self.transcript(systemPrompt: systemPrompt, history: history)
            )
        }
        appleSession = session
        appleSessionInstructions = systemPrompt
        return session
    }

    /// Builds a rehydration transcript: a leading `.instructions` entry carrying
    /// the system prompt, followed by one `.prompt`/`.response` entry per turn.
    @available(iOS 26.0, *)
    private static func transcript(
        systemPrompt: String,
        history: [AIChatTurn]
    ) -> Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(
                Transcript.Instructions(
                    segments: [.text(Transcript.TextSegment(content: systemPrompt))],
                    toolDefinitions: []
                )
            )
        ]
        for turn in history {
            let segment = Transcript.Segment.text(Transcript.TextSegment(content: turn.content))
            if turn.role == "assistant" {
                entries.append(.response(Transcript.Response(assetIDs: [], segments: [segment])))
            } else {
                entries.append(.prompt(Transcript.Prompt(segments: [segment])))
            }
        }
        return Transcript(entries: entries)
    }

    /// Reset the on-device session — call when starting a new conversation.
    func resetAppleSession() {
        appleSession = nil
        appleSessionInstructions = ""
    }
}
