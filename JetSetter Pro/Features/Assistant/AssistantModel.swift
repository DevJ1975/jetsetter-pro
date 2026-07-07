// File: Features/Assistant/AssistantModel.swift
//
// Claude (Anthropic) wire types shared by `AIService` (chat/persona streaming) and
// `PackingListService` (non-streaming decode). The standalone "Assistant" chat
// surface these once backed was retired in favor of IRIS (the sole chat surface);
// only these request/response models remain, since Claude is still used as a
// server-side fallback and for one-shot generation.

import Foundation

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

/// The delta payload inside a `content_block_delta` event, or the top-level delta
/// of a `message_delta` event (which carries `stop_reason` when the turn ends).
struct ClaudeStreamDelta: Decodable {
    let type: String?
    let text: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, text
        case stopReason = "stop_reason"
    }
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
