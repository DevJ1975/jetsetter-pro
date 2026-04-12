// File: Features/Assistant/AssistantModel.swift

import Foundation

// MARK: - UI Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum ChatRole: Equatable {
    case user
    case assistant
}

// MARK: - Claude API Request

/// The full request body sent to POST /v1/messages.
struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }
}

/// A single turn in the conversation history sent to Claude.
struct ClaudeMessage: Codable {
    let role: String    // "user" or "assistant"
    let content: String
}

// MARK: - Claude Streaming SSE Events

/// A single server-sent event from the streaming endpoint.
struct ClaudeStreamEvent: Decodable {
    let type: String
    let delta: ClaudeStreamDelta?
}

/// The delta payload inside a `content_block_delta` event.
struct ClaudeStreamDelta: Decodable {
    let type: String?
    let text: String?
}

// MARK: - Claude API Response (non-streaming fallback)

struct ClaudeResponse: Decodable {
    let id: String
    let content: [ClaudeContentBlock]
    let model: String
    let stopReason: String?
    let usage: ClaudeUsage

    var firstTextContent: String? {
        content.first(where: { $0.type == "text" })?.text
    }
}

struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
}

struct ClaudeUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - System Prompt

extension ClaudeRequest {
    static let travelSystemPrompt = """
    You are Jetsetter's AI travel assistant — a knowledgeable, friendly, and concise travel expert.

    You help users with:
    - Flight status, delays, and airport information
    - Hotel and destination recommendations
    - Packing tips and travel checklists
    - Visa, passport, and entry requirements
    - Local culture, customs, and safety tips
    - Itinerary planning and time zone guidance
    - Ground transport and rental car advice
    - Travel expense tips and currency information

    Keep responses clear and conversational. Use bullet points for lists. \
    When relevant, remind users they can track flights, log expenses, and manage bookings directly in the Jetsetter app.
    """
}

// MARK: - Sample Data (Previews)

extension ChatMessage {
    static let sampleConversation: [ChatMessage] = [
        ChatMessage(role: .user, content: "What should I pack for a week in Tokyo in April?"),
        ChatMessage(role: .assistant, content: """
        Great choice — Tokyo in April is beautiful! Here's what to pack:

        **Clothing**
        - Light layers (temps range 10–18°C / 50–65°F)
        - A waterproof jacket — spring showers are common
        - Comfortable walking shoes (you'll walk a lot!)
        - Smart-casual outfits for restaurants

        **Essentials**
        - IC Card (Suica or Pasmo) for trains — get at the airport
        - Pocket Wi-Fi or eSIM
        - Power adapter (Japan uses Type A plugs)
        - Cash — many smaller places are cash-only

        **Tips**
        - Cherry blossoms peak in late March to early April — book parks early
        - Download Google Translate with Japanese offline support
        """)
    ]
}
