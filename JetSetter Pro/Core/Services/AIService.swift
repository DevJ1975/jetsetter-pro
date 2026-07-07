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
        if MockDataService.isEnabled {
            return .mock
        }
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
        case .mock:              return "Demo mode"
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
                // The session maintains its own transcript across requests, so
                // we send only the new user message and let FoundationModels
                // manage context.
                let session = self.sessionForAppleIntelligence(systemPrompt: systemPrompt)
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    // Context window exceeded → drop the session so the next
                    // request gets a fresh one. Propagate other errors.
                    self.appleSession = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private func sessionForAppleIntelligence(systemPrompt: String) -> LanguageModelSession {
        if let existing = appleSession as? LanguageModelSession, appleSessionInstructions == systemPrompt {
            return existing
        }
        let session = LanguageModelSession(instructions: systemPrompt)
        appleSession = session
        appleSessionInstructions = systemPrompt
        return session
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
                    continuation.finish(throwing: URLError(.badURL))
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
                    // worth adding — the system prompt is well under Claude's 1024-token
                    // cache minimum, so it would never cache.)
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
                        continuation.finish(throwing: URLError(.badServerResponse))
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

    // MARK: - Mock (demo mode)

    private func streamFromMock(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 800...1_400)))
                let reply = MockDataService.mockAssistantResponse(for: prompt)
                var cumulative = ""
                // Cap total "typing" time (~2.5s) so a long mock reply doesn't crawl.
                let perChar = min(12, max(1, 2_500 / max(reply.count, 1)))
                for char in reply {
                    cumulative.append(char)
                    continuation.yield(cumulative)
                    try? await Task.sleep(for: .milliseconds(perChar))
                }
                continuation.finish()
            }
        }
    }
}
