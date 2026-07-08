// File: Core/Services/EmailIntelligence/TravelEmailParsingService.swift
//
// Turns raw forwarded-email text into structured travel entities.
// Provider routing mirrors AIService:
//   1. Apple Intelligence (on-device, FoundationModels guided generation) —
//      free, private: the email never leaves the device.
//   2. Anthropic Claude (if API key configured) — JSON-contract fallback,
//      same shape as PackingListService's proven call.
//   3. Mock sample — demo mode / nothing configured.

import Foundation
import FoundationModels

@MainActor
final class TravelEmailParsingService {

    static let shared = TravelEmailParsingService()
    private init() {}

    // MARK: - Provider selection (same policy as AIService.activeProvider)

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
        case .appleIntelligence: return "Parsed on-device — email never leaves your iPhone"
        case .claude:            return "Parsed by Claude"
        case .mock:              return "Demo mode — sample parse"
        }
    }

    // MARK: - Entry point

    /// Parses one email's raw text into structured entities.
    func parse(emailText: String) async throws -> ParsedTravelEmail {
        let text = Self.prepared(emailText)
        guard !text.isEmpty else { return ParsedTravelEmail() }

        switch activeProvider {
        case .appleIntelligence:
            if #available(iOS 26.0, *) {
                return try await parseOnDevice(text)
            }
            return Self.mockParse()
        case .claude:
            return try await parseWithClaude(text)
        case .mock:
            return Self.mockParse()
        }
    }

    // MARK: - Input preparation

    /// Trims obvious noise so long emails fit the on-device 4096-token
    /// context: strips long base64/attachment runs and hard-caps length.
    static func prepared(_ raw: String, maxCharacters: Int = 6_000) -> String {
        var lines = raw.components(separatedBy: .newlines)
        // Drop classic base64 attachment bodies: long runs of 60+ char
        // lines with no spaces.
        lines.removeAll { line in
            line.count >= 60 && !line.contains(" ") &&
            line.range(of: "^[A-Za-z0-9+/=]+$", options: .regularExpression) != nil
        }
        let joined = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(joined.prefix(maxCharacters))
    }

    // MARK: - Apple Intelligence (structured, on-device)

    @available(iOS 26.0, *)
    private func parseOnDevice(_ text: String) async throws -> ParsedTravelEmail {
        // Fresh session per parse: extraction is stateless, and a shared
        // transcript would only burn the 4096-token context window.
        let session = LanguageModelSession(instructions: TravelEmailPrompt.instructions)
        let response = try await session.respond(
            to: text,
            generating: ParsedTravelEmailGen.self
        )
        return response.content.toDTO()
    }

    // MARK: - Claude fallback (JSON contract)

    private func parseWithClaude(_ text: String) async throws -> ParsedTravelEmail {
        guard let url = Endpoints.Claude.messagesURL else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in Endpoints.Claude.headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        let body: [String: Any] = [
            // Same model AIService uses for its Claude path.
            "model": "claude-sonnet-4-6",
            "max_tokens": 2048,
            "system": TravelEmailPrompt.instructions + "\n\n" + TravelEmailPrompt.jsonContract,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let textOut = claudeResponse.firstTextContent else {
            throw URLError(.cannotParseResponse)
        }
        return Self.decodeContract(from: textOut)
    }

    /// Strips markdown fences (if any) and decodes the JSON contract.
    /// Returns an empty result rather than throwing on a malformed reply.
    static func decodeContract(from text: String) -> ParsedTravelEmail {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n")
                .dropFirst()
                .joined(separator: "\n")
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let data = cleaned.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ParsedTravelEmail.self, from: data)
        else {
            return ParsedTravelEmail()
        }
        return parsed
    }

    // MARK: - Mock (demo mode)

    static func mockParse() -> ParsedTravelEmail {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let plusDays: (Int, Int) -> String = { days, hour in
            var comps = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: days, to: Date()) ?? Date())
            comps.hour = hour
            return f.string(from: cal.date(from: comps) ?? Date())
        }

        var result = ParsedTravelEmail()

        var flight = ParsedFlight(flightNumber: "DL0483")
        flight.airline = "Delta Air Lines"
        flight.departureAirport = "JFK"
        flight.arrivalAirport = "SFO"
        flight.departureLocal = plusDays(5, 9)
        flight.arrivalLocal = plusDays(5, 12)
        flight.seat = "2C"
        flight.confirmationNumber = "DLX4R2"
        flight.confidence = 0.97
        result.flights = [flight]

        var hotel = ParsedHotel(name: "St. Regis San Francisco")
        hotel.address = "125 3rd St, San Francisco, CA"
        hotel.checkInLocal = plusDays(5, 15)
        hotel.checkOutLocal = plusDays(8, 11)
        hotel.confirmationNumber = "SR-99841"
        hotel.confidence = 0.94
        result.hotels = [hotel]

        var meeting = ParsedMeeting(title: "Q3 Partner Review — Acme Corp")
        meeting.startLocal = plusDays(6, 10)
        meeting.endLocal = plusDays(6, 11)
        meeting.location = "Acme HQ, 1 Market St, San Francisco"
        meeting.organizer = "sarah@acme.com"
        meeting.confidence = 0.91
        result.meetings = [meeting]

        return result
    }
}
