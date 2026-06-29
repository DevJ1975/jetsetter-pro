// File: Features/IRIS/IRISChatViewModel.swift

import Foundation
import SwiftUI
import Combine

@MainActor
final class IRISChatViewModel: ObservableObject {

    @Published private(set) var messages: [IRISMessage] = []
    @Published private(set) var streamingContent: String = ""
    @Published private(set) var isResponding: Bool = false
    @Published var errorMessage: String?

    /// Static greeting shown on first open. Tailored if memory exists.
    @Published private(set) var greeting: String = ""

    init() {
        composeGreeting()
    }

    // MARK: - Send

    /// Sends a prompt and returns IRIS's final reply (or nil on error/empty),
    /// so a voice loop can speak it. The `@discardableResult` keeps existing
    /// fire-and-forget callers unchanged.
    @discardableResult
    func send(_ text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        messages.append(IRISMessage(role: .user, content: trimmed))
        streamingContent = ""
        isResponding = true
        errorMessage = nil
        defer {
            isResponding = false
            streamingContent = ""
        }

        let stream = IRISAgentService.shared.streamResponse(prompt: trimmed)
        do {
            for try await snapshot in stream {
                streamingContent = snapshot
            }
        } catch {
            print("[IRISChatViewModel] streamResponse failed: \(error)")
            errorMessage = "IRIS hit a snag. Try again?"
            return nil
        }

        guard !streamingContent.isEmpty else {
            errorMessage = "IRIS didn't respond. Try again."
            return nil
        }
        let reply = streamingContent
        messages.append(IRISMessage(role: iris, content: reply))
        return reply
    }

    /// Appends an IRIS-voiced line after a confirmed/cancelled action so the
    /// transcript reflects the outcome. Exposed because `messages` is private(set).
    func recordActionResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(IRISMessage(role: .assistant, content: trimmed))
    }

    // MARK: - Conversation control

    func clear() {
        messages.removeAll()
        IRISAgentService.shared.resetConversation()
        composeGreeting()
    }

    // MARK: - Greeting

    private func composeGreeting() {
        let known = IRISMemory.shared.preferences.count
        if known == 0 {
            greeting = "Hi, I'm IRIS — your travel agent in your pocket. Tell me about your next trip or just say hi to get started."
        } else {
            greeting = "Welcome back. I've kept track of \(known) \(known == 1 ? "preference" : "preferences") about how you like to travel. What's on your mind?"
        }
    }

    // MARK: - Convenience

    private let iris = IRISMessage.Role.assistant
}

// MARK: - Message model

struct IRISMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role { case user, assistant }

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
