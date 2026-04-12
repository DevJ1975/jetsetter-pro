// File: Features/Assistant/AssistantViewModel.swift

import Combine
import Foundation

// MARK: - AssistantViewModel

/// Manages AI assistant conversation state and Claude API streaming.
/// Streams tokens from the Claude API so responses appear word-by-word in the UI.
@MainActor
final class AssistantViewModel: ObservableObject {

    // MARK: - Published State

    @Published var messages: [ChatMessage] = []

    /// Accumulates streamed text while Claude is still generating.
    /// The view shows this as a live bubble; cleared once streaming completes.
    @Published var streamingContent: String = ""

    /// True from the moment a request is sent until the response is fully received.
    @Published var isWaitingForResponse: Bool = false

    @Published var errorMessage: String? = nil

    // MARK: - Private State

    private var conversationHistory: [ClaudeMessage] = []

    // Cached to avoid re-allocating on every message send
    private let tripDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let tripDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    // MARK: - Send Message

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        conversationHistory.append(ClaudeMessage(role: "user", content: trimmed))

        isWaitingForResponse = true
        streamingContent = ""
        errorMessage = nil

        defer {
            isWaitingForResponse = false
            streamingContent = ""
        }

        // ── Mock path ─────────────────────────────────────────────────────────
        if MockDataService.isEnabled {
            let delayMs = Int.random(in: 800...1_400)
            try? await Task.sleep(for: .milliseconds(delayMs))
            let reply = MockDataService.mockAssistantResponse(for: trimmed)

            // Simulate streaming by dripping characters
            for char in reply {
                streamingContent.append(char)
                try? await Task.sleep(for: .milliseconds(12))
            }

            messages.append(ChatMessage(role: .assistant, content: reply))
            conversationHistory.append(ClaudeMessage(role: "assistant", content: reply))
            return
        }
        // ─────────────────────────────────────────────────────────────────────

        guard let url = Endpoints.Claude.messagesURL else {
            errorMessage = "Could not build the request URL."
            conversationHistory.removeLast()
            return
        }

        let request = ClaudeRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 1024,
            system: buildSystemPrompt(),
            messages: conversationHistory,
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

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid server response."
                conversationHistory.removeLast()
                return
            }
            guard httpResponse.statusCode == 200 else {
                errorMessage = httpResponse.statusCode == 401
                    ? "Invalid API key. Check your Anthropic key in Endpoints.swift."
                    : "Server error (\(httpResponse.statusCode)). Please try again."
                conversationHistory.removeLast()
                return
            }

            let decoder = JSONDecoder()

            // Parse SSE lines: each meaningful line starts with "data: "
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                guard !jsonString.isEmpty else { continue }

                guard let data = jsonString.data(using: .utf8),
                      let event = try? decoder.decode(ClaudeStreamEvent.self, from: data)
                else { continue }

                // Only content_block_delta with type text_delta carries text
                if event.type == "content_block_delta",
                   event.delta?.type == "text_delta",
                   let text = event.delta?.text {
                    streamingContent += text
                }
            }

            // Commit the fully-streamed response
            let reply = streamingContent
            if !reply.isEmpty {
                messages.append(ChatMessage(role: .assistant, content: reply))
                conversationHistory.append(ClaudeMessage(role: "assistant", content: reply))
            } else {
                errorMessage = "Received an empty response. Please try again."
                conversationHistory.removeLast()
            }

        } catch is CancellationError {
            // Task was cancelled (e.g. user navigated away) — discard silently
            conversationHistory.removeLast()
        } catch {
            errorMessage = "Something went wrong. Please try again."
            conversationHistory.removeLast()
        }
    }

    // MARK: - Clear Conversation

    func clearConversation() {
        messages = []
        conversationHistory = []
        streamingContent = ""
        errorMessage = nil
    }

    // MARK: - System Prompt with Trip Context

    /// Builds the system prompt, injecting the user's next trip if one exists.
    private func buildSystemPrompt() -> String {
        var context = ""

        if let data = UserDefaults.standard.data(forKey: "jetsetter_trips"),
           let trips = try? tripDecoder.decode([Trip].self, from: data) {
            let today = Calendar.current.startOfDay(for: Date())
            if let next = trips
                .filter({ $0.startDate >= today })
                .min(by: { $0.startDate < $1.startDate }) {
                context = """


                User context: The user has an upcoming trip to \(next.destination) \
                (\(tripDateFormatter.string(from: next.startDate)) – \(tripDateFormatter.string(from: next.endDate))). \
                Tailor responses to be relevant to this destination when appropriate.
                """
            }
        }

        return ClaudeRequest.travelSystemPrompt + context
    }
}
