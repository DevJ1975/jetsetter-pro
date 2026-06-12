// File: Features/Assistant/AssistantViewModel.swift
// Drives the AI assistant chat. Streams cumulative response snapshots from
// AIService, which picks Apple Intelligence → Claude → Mock based on what's
// available at request time.

import Combine
import Foundation

@MainActor
final class AssistantViewModel: ObservableObject {

    // MARK: - Published State

    @Published var messages: [ChatMessage] = []
    @Published var streamingContent: String = ""
    @Published var isWaitingForResponse: Bool = false
    @Published var errorMessage: String? = nil

    /// Human-readable badge shown under the chat header.
    @Published var providerStatusLabel: String = AIService.shared.providerStatusLabel

    // MARK: - Private

    private var conversationHistory: [AIChatTurn] = []

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
        let userTurn = AIChatTurn(role: "user", content: trimmed)

        isWaitingForResponse = true
        streamingContent = ""
        errorMessage = nil
        providerStatusLabel = AIService.shared.providerStatusLabel

        defer {
            isWaitingForResponse = false
            streamingContent = ""
        }

        let stream = AIService.shared.streamResponse(
            prompt: trimmed,
            history: conversationHistory,
            systemPrompt: buildSystemPrompt()
        )

        do {
            for try await snapshot in stream {
                streamingContent = snapshot
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Something went wrong. Please try again."
            return
        }

        let reply = streamingContent
        guard !reply.isEmpty else {
            errorMessage = "Received an empty response. Please try again."
            return
        }

        messages.append(ChatMessage(role: .assistant, content: reply))
        conversationHistory.append(userTurn)
        conversationHistory.append(AIChatTurn(role: "assistant", content: reply))
    }

    // MARK: - Clear Conversation

    func clearConversation() {
        messages = []
        conversationHistory = []
        streamingContent = ""
        errorMessage = nil
        AIService.shared.resetAppleSession()
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
