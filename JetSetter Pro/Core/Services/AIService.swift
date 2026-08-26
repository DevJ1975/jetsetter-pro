// File: Core/Services/AIService.swift
//
// Unified AI provider for the Assistant. Routes requests in this order:
//   1. Apple Intelligence (on-device, FoundationModels) — free, private, fast
//   2. Anthropic Claude (if API key is configured) — capable fallback
//   3. Mock responses — always works (used in MockDataService demo mode)
//
// All paths emit cumulative response snapshots so the view layer can simply
// assign each value to its `streamingContent` state without tracking deltas.

import Foundation
import FoundationModels

// MARK: - Provider

enum AIProvider: String, Sendable {
    case appleIntelligence
    case claude
    case mock

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .claude:            return "Claude"
        case .mock:              return "Demo Mode"
        }
    }
}

// MARK: - History Entry

struct AIChatTurn: Sendable {
    let role: String   // "user" or "assistant"
    let content: String
}

// MARK: - Claude Error

/// A non-200 from the Claude Messages API. Decodes Anthropic's
/// `{"type":"error","error":{"type","message"}}` envelope so the failure
/// carries an actionable reason (invalid key vs rate limit vs overloaded)
/// rather than a generic `URLError`.
struct ClaudeError: LocalizedError {
    let statusCode: Int
    let apiErrorType: String?
    let apiMessage: String?

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        var type: String?
        var message: String?
        if let data = body.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(ClaudeErrorEnvelope.self, from: data) {
            type = envelope.error.type
            message = envelope.error.message
        }
        self.apiErrorType = type
        self.apiMessage = message
    }

    var errorDescription: String? {
        // Prefer Anthropic's own message; otherwise map the status code to a
        // recognizable cause.
        if let apiMessage, !apiMessage.isEmpty {
            return apiMessage
        }
        switch statusCode {
        case 401:        return "Invalid or missing Claude API key."
        case 403:        return "This Claude API key lacks the required permissions."
        case 429:        return "Claude rate limit reached — please try again shortly."
        case 500...599:  return "Claude is temporarily unavailable — please try again."
        default:         return "Claude request failed (HTTP \(statusCode))."
        }
    }

    private struct ClaudeErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let type: String?
            let message: String?
        }
        let error: Detail
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

    // MARK: - Provider selection

    /// Picks the best provider available right now. Recomputed per request so
    /// the user can toggle Apple Intelligence in Settings mid-session.
    var activeProvider: AIProvider {
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .appleIntelligence
            default:
                return AppSecrets.isConfigured(.anthropic) ? .claude : .mock
            }
        } else {
            return AppSecrets.isConfigured(.anthropic) ? .claude : .mock
        }
    }

    var providerStatusLabel: String {
        switch activeProvider {
        case .appleIntelligence: return "Powered by Apple Intelligence"
        case .claude:            return "Powered by Claude"
        case .mock:              return "AI unavailable"
        }
    }

    // MARK: - Streaming entry point

    /// Streams an AI response. Each yielded String is the *cumulative* content
    /// generated so far; callers should overwrite their UI buffer with each value.
    func streamResponse(
        prompt: String,
        history: [AIChatTurn],
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        switch activeProvider {
        case .appleIntelligence:
            if #available(iOS 26.0, *) {
                return streamFromAppleIntelligence(
                    prompt: prompt,
                    history: history,
                    systemPrompt: systemPrompt
                )
            } else {
                return streamFromMock(prompt: prompt)
            }
        case .claude:
            return streamFromClaude(
                prompt: prompt,
                history: history,
                systemPrompt: systemPrompt
            )
        case .mock:
            return streamFromMock(prompt: prompt)
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
            Task { @MainActor in
                // A cached session maintains its own transcript across requests, so
                // for a warm session we send only the new user message. When the
                // session has to be (re)created — first turn, changed system prompt,
                // or after a context-window reset — it is seeded by replaying
                // `history` so prior turns survive, matching the Claude path.
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

    // MARK: - Claude (fallback)

    private func streamFromClaude(
        prompt: String,
        history: [AIChatTurn],
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let url = Endpoints.Claude.messagesURL else {
                    continuation.finish(throwing: APIError.invalidURL)
                    return
                }

                var historyForRequest = history.map {
                    ClaudeMessage(role: $0.role, content: $0.content)
                }
                historyForRequest.append(ClaudeMessage(role: "user", content: prompt))

                let request = ClaudeRequest(
                    // Current Sonnet. The previous id (claude-sonnet-4-20250514)
                    // retired 2026-06-15 and now 404s.
                    model: "claude-sonnet-4-6",
                    // 1024 truncated multi-part travel answers mid-thought; 4096 gives
                    // room for a full itinerary/packing reply. (Prompt caching is not
                    // worth adding — the system prompt is well under Sonnet 4.6's
                    // 2048-token cache minimum, so it would never cache.)
                    maxTokens: 4096,
                    system: systemPrompt,
                    messages: historyForRequest,
                    stream: true
                )

                do {
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.httpBody = try JSONEncoder().encode(request)
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    for (key, value) in Endpoints.Claude.headers {
                        urlRequest.setValue(value, forHTTPHeaderField: key)
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // Anthropic returns {"type":"error","error":{"type","message"}}
                        // on failures. Read the body so we can surface an actionable
                        // reason (bad key / rate limit / etc.) instead of an opaque
                        // "bad server response".
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        continuation.finish(
                            throwing: ClaudeError(statusCode: http.statusCode, body: body)
                        )
                        return
                    }

                    let decoder = JSONDecoder()
                    var cumulative = ""
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard !jsonString.isEmpty,
                              let data = jsonString.data(using: .utf8),
                              let event = try? decoder.decode(ClaudeStreamEvent.self, from: data)
                        else { continue }
                        if event.type == "content_block_delta",
                           event.delta?.type == "text_delta",
                           let text = event.delta?.text {
                            cumulative += text
                            continuation.yield(cumulative)
                        } else if event.type == "message_delta",
                                  event.delta?.stopReason == "max_tokens" {
                            // Hit the token ceiling — signal the cut-off rather than
                            // ending mid-sentence with no explanation.
                            cumulative += "\n\n…(I ran long and had to stop — ask me to continue.)"
                            continuation.yield(cumulative)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Unavailable fallback

    /// Terminal fallback when neither Apple Intelligence nor a configured Claude
    /// key is available. Emits a single honest message rather than fabricated
    /// content.
    private func streamFromMock(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("AI features aren't available on this device.")
            continuation.finish()
        }
    }
}
