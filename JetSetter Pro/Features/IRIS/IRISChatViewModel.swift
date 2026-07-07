// File: Features/IRIS/IRISChatViewModel.swift

import Foundation
import SwiftUI

@MainActor
@Observable
final class IRISChatViewModel {

    private(set) var messages: [IRISMessage] = []
    private(set) var streamingContent: String = ""
    private(set) var isResponding: Bool = false
    var errorMessage: String?

    /// Assistant messages the user has already rated (thumbs), so the control hides
    /// after one vote and we don't double-count in the metrics ledger.
    private(set) var ratedMessageIDs: Set<UUID> = []

    /// Static greeting shown on first open. Tailored if memory exists.
    private(set) var greeting: String = ""

    init() {
        composeGreeting()
    }

    // MARK: - Send

    /// Sends a prompt and returns IRIS's final reply (or nil on error/empty),
    /// so a voice loop can speak it. The `@discardableResult` keeps existing
    /// fire-and-forget callers unchanged.
    @discardableResult
    func send(_ text: String) async -> String? {
        // Reentrancy guard: a second send() while the first is still streaming
        // would race two LanguageModelSession streams and let one defer clear
        // streamingContent / isResponding mid-stream of the other, garbling the
        // bubble. Callers include the send button, TextField.onSubmit, and the
        // voice loop — not all of them are gated on canSend.
        guard !isResponding else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        messages.append(IRISMessage(role: .user, content: trimmed))
        streamingContent = ""
        isResponding = true
        errorMessage = nil
        let profileActive = IRISAgentService.shared.isProfileActive
        defer {
            isResponding = false
            streamingContent = ""
        }

        let stream = IRISAgentService.shared.streamResponse(prompt: trimmed)
        // Snapshots are cumulative, but a final empty/whitespace snapshot must not
        // discard the content we already streamed. Retain the last snapshot that
        // actually carried (non-whitespace) text and treat that as the reply.
        var lastNonEmpty = ""
        do {
            for try await snapshot in stream {
                streamingContent = snapshot
                if !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastNonEmpty = snapshot
                }
            }
        } catch {
            print("[IRISChatViewModel] streamResponse failed: \(error)")
            errorMessage = IRISAgentService.shared.friendlyErrorMessage(for: error)
            return nil
        }

        guard !lastNonEmpty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "IRIS didn't respond. Try again."
            return nil
        }
        let reply = lastNonEmpty
        messages.append(IRISMessage(role: iris, content: reply, profileInjected: profileActive))
        return reply
    }

    /// Voice-loop entry point. Uses IRIS's non-streaming `respond(to:)` (Apple's
    /// recommendation for latency-sensitive use) since the voice controller only
    /// needs the final text to speak — no need to render partial snapshots.
    @discardableResult
    func sendSpoken(_ text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        messages.append(IRISMessage(role: .user, content: trimmed))
        isResponding = true
        errorMessage = nil
        let profileActive = IRISAgentService.shared.isProfileActive
        defer { isResponding = false }

        let reply: String
        do {
            if #available(iOS 26.0, *) {
                reply = try await IRISAgentService.shared.respond(prompt: trimmed)
            } else {
                // Non-streaming path is iOS 26+. On older OSes (demo mode) aggregate
                // the streamed snapshots into the final string.
                reply = try await aggregatedStream(trimmed)
            }
        } catch {
            errorMessage = IRISAgentService.shared.friendlyErrorMessage(for: error)
            return nil
        }

        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "IRIS didn't respond. Try again."
            return nil
        }
        messages.append(IRISMessage(role: iris, content: reply, profileInjected: profileActive))
        return reply
    }

    /// Records the user's thumbs rating for an assistant reply into the metrics
    /// ledger, tagged with whether the learned profile was in context — the input to
    /// `SuggestionMetricsStore.turns.profileLift`. One vote per message.
    func rateReply(_ message: IRISMessage, helpful: Bool) {
        guard message.role == .assistant, !ratedMessageIDs.contains(message.id) else { return }
        ratedMessageIDs.insert(message.id)
        SuggestionMetricsStore.shared.recordHelpfulVote(
            profileInjected: message.profileInjected, helpful: helpful
        )
    }

    /// Consumes a streaming response fully and returns the final cumulative text.
    private func aggregatedStream(_ prompt: String) async throws -> String {
        var last = ""
        for try await snapshot in IRISAgentService.shared.streamResponse(prompt: prompt) {
            last = snapshot
        }
        return last
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
        // A returning user may have zero *explicitly stated* preferences yet still
        // have a rich *inferred* profile from the learning layer (seats, airlines,
        // cities). Treat that learned context as "we know this user" too, so they
        // get the warm "Welcome back" copy instead of the cold first-run line.
        let hasLearnedProfile = !TravelProfileStore.shared.profile.isEmpty
        if known == 0 && !hasLearnedProfile {
            greeting = "Hi, I'm IRIS — your travel agent in your pocket. Tell me about your next trip or just say hi to get started."
        } else if known == 0 {
            greeting = "Welcome back. I've picked up on how you like to travel from your trips so far. What's on your mind?"
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
    /// For assistant replies: whether the learned profile was in context for this
    /// turn. Drives the `profileLift` metric when the user rates the reply.
    let profileInjected: Bool

    enum Role { case user, assistant }

    init(role: Role, content: String, profileInjected: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.profileInjected = profileInjected
    }
}
