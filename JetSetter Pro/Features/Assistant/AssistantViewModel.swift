// File: Features/Assistant/AssistantViewModel.swift

import Foundation
import Combine

// MARK: - AssistantViewModel

/// Manages the AI assistant conversation state and Claude API communication.
/// Maintains full conversation history so Claude has context for follow-up questions.
@MainActor
final class AssistantViewModel: ObservableObject {

    // MARK: - Published State

    /// Messages displayed in the chat UI
    @Published var messages: [ChatMessage] = []

    /// True while waiting for Claude to respond
    @Published var isWaitingForResponse: Bool = false

    /// Non-nil when an error occurs sending a message
    @Published var errorMessage: String? = nil

    // MARK: - Private State

    /// Full conversation history sent to Claude on every request for context
    private var conversationHistory: [ClaudeMessage] = []

    // MARK: - Send Message

    /// Sends a user message to Claude and appends the response to the conversation.
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add user message to UI immediately
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Add to history for Claude context
        conversationHistory.append(ClaudeMessage(role: "user", content: trimmed))

        isWaitingForResponse = true
        errorMessage = nil

        defer { isWaitingForResponse = false }

        // ── Mock path ─────────────────────────────────────────────────────────
        if MockDataService.isEnabled {
            let delayMs = Int.random(in: 1_200...2_000)
            try? await Task.sleep(for: .milliseconds(delayMs))
            let reply = MockDataService.mockAssistantResponse(for: trimmed)
            messages.append(ChatMessage(role: .assistant, content: reply))
            conversationHistory.append(ClaudeMessage(role: "assistant", content: reply))
            return
        }
        // ─────────────────────────────────────────────────────────────────────

        guard let url = Endpoints.Claude.messagesURL else {
            errorMessage = "Could not build the request URL."
            return
        }

        let request = ClaudeRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 1024,
            system: ClaudeRequest.travelSystemPrompt,
            messages: conversationHistory
        )

        do {
            let response: ClaudeResponse = try await APIClient.shared.post(
                url: url,
                body: request,
                headers: Endpoints.Claude.headers
            )

            guard let replyText = response.firstTextContent else {
                errorMessage = "Received an empty response. Please try again."
                // Remove the last history entry since we have no valid response to pair it with
                conversationHistory.removeLast()
                return
            }

            // Append assistant reply to both UI and history
            messages.append(ChatMessage(role: .assistant, content: replyText))
            conversationHistory.append(ClaudeMessage(role: "assistant", content: replyText))

        } catch let error as APIError {
            errorMessage = error.errorDescription
            // Remove the unanswered user message from history to keep history consistent
            conversationHistory.removeLast()
        } catch {
            errorMessage = "Something went wrong. Please try again."
            conversationHistory.removeLast()
        }
    }

    // MARK: - Clear Conversation

    /// Resets the conversation to a blank state.
    func clearConversation() {
        messages = []
        conversationHistory = []
        errorMessage = nil
    }
}
