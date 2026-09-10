// File: Core/Services/IRIS/IRISAgentService.swift
//
// IRIS sits one layer above AIService. She composes Instructions + her tool
// catalog into a single LanguageModelSession, streams responses, and exposes a
// simple chat API to the view layer.
//
// Two design points worth knowing:
//   • The SESSION instructions hold only IRIS's stable identity + what she's
//     learned (see IRISPersonality). The volatile live snapshot (current trip,
//     expenses, "now"-relative labels) is injected per-turn via `composeTurnPrompt`
//     so the session — and its transcript — isn't torn down every time the clock
//     ticks or the user logs an expense.
//   • A single shared session can't handle two prompts at once (it throws
//     `.concurrentRequests`), and the voice loop + text field both feed it, so an
//     `isResponding` guard serializes them at the service layer.

import Foundation
import FoundationModels

@MainActor
final class IRISAgentService {

    static let shared = IRISAgentService()

    /// Cached on-device session. We recreate when instructions change or the
    /// transcript needs to be cleared.
    // Stored as `Any?` so this property can exist on our iOS 18 deployment
    // target; the concrete `LanguageModelSession` type is iOS 26-only and is
    // only referenced inside `if #available` / `@available` contexts below.
    private var session: Any?
    private var sessionInstructions: String = ""

    /// Guards the shared session against overlapping prompts (voice + text). A
    /// `LanguageModelSession` throws `.concurrentRequests` if prompted while it's
    /// still responding, so we reject the second caller with `IRISError.busy`.
    private var isResponding = false

    /// True until the live-context preamble has been injected once for the current
    /// session. We ground the first turn with the traveler's live snapshot, then rely
    /// on the transcript, rather than re-sending it on every turn in a 4K window.
    private var needsContextPrefix = false

    /// True when IRIS can run on this device (Apple Intelligence, iOS 26+).
    var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default:         return false
            }
        } else {
            return false
        }
    }

    var unavailabilityReason: String? {
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This device doesn't support Apple Intelligence, which powers IRIS."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence isn't enabled. Turn it on in Settings to chat with IRIS."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading. Try again in a few minutes."
            case .unavailable:
                return "IRIS is temporarily unavailable on this device."
            }
        } else {
            return "IRIS requires Apple Intelligence, available on iOS 26 or later on a supported device."
        }
    }

    private init() {}

    /// Whether the learned profile is currently non-empty — i.e. it's being injected
    /// into IRIS's instructions. The VM tags each reply with this so the metrics
    /// ledger can measure whether personalization actually helps (`profileLift`).
    var isProfileActive: Bool {
        !TravelProfileStore.shared.profile.summaryForPrompt().isEmpty
    }

    // MARK: - Chat API (streaming — for the text UI)

    /// Streams a response from IRIS. Each yielded String is the cumulative
    /// content so far; the view layer should overwrite its buffer with each.
    func streamResponse(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                guard self.isAvailable, #available(iOS 26.0, *) else {
                    continuation.finish(throwing: IRISError.unavailable)
                    return
                }
                // Serialize against the voice loop / a rapid double-send.
                guard !self.isResponding else {
                    continuation.finish(throwing: IRISError.busy)
                    return
                }
                self.isResponding = true
                defer { self.isResponding = false }

                self.noteTurn()
                let session = self.activeSession()
                let turnPrompt = self.composeTurnPrompt(prompt)
                do {
                    let stream = session.streamResponse(to: turnPrompt)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    self.handleGenerationFailure(error)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Chat API (non-streaming — for the voice loop)

    /// Produces IRIS's full reply in one shot. Apple recommends the non-streaming
    /// `respond(to:)` over `streamResponse` for latency-sensitive/background use to
    /// reduce `rateLimited` errors — and the voice loop only needs the final text to
    /// speak, so streaming bought nothing there.
    @available(iOS 26.0, *)
    func respond(prompt: String) async throws -> String {
        guard isAvailable else { throw IRISError.unavailable }
        guard !isResponding else { throw IRISError.busy }
        isResponding = true
        defer { isResponding = false }

        noteTurn()
        let session = activeSession()
        do {
            let response = try await session.respond(to: composeTurnPrompt(prompt))
            return response.content
        } catch {
            handleGenerationFailure(error)
            throw error
        }
    }

    /// Begins a fresh conversation (clears transcript). Memory persists.
    func resetConversation() {
        session = nil
        sessionInstructions = ""
        needsContextPrefix = false
    }

    // MARK: - Turn assembly

    /// Prepends the live traveler snapshot to the first user turn of a session so
    /// IRIS is grounded from the start, without baking that volatile data into the
    /// session instructions (which would churn the session). Later turns pass through.
    private func composeTurnPrompt(_ userPrompt: String) -> String {
        guard needsContextPrefix else { return userPrompt }
        needsContextPrefix = false
        let snapshot = IRISContext.currentSnapshot()
        guard !snapshot.isEmpty else { return userPrompt }
        return """
        [Live traveler context — ground your reply in this; don't recite it verbatim]
        \(snapshot)

        \(userPrompt)
        """
    }

    /// Records one IRIS turn for the metrics ledger, tagged with whether the learned
    /// profile was available to inject — so `profileLift` can later tell us if
    /// personalization actually helps.
    private func noteTurn() {
        SuggestionMetricsStore.shared.recordIRISTurn(profileInjected: isProfileActive)
    }

    // MARK: - Error handling

    /// Only a context-window overflow warrants discarding the session (its transcript
    /// outgrew the 4K window); every other generation error keeps the session so the
    /// conversation survives. The VM maps errors to user-facing copy separately.
    /// (`do { throw } catch` is the idiom Apple documents for matching these cases —
    /// they carry associated values, so bare `case` labels don't match cleanly.)
    @available(iOS 26.0, *)
    private func handleGenerationFailure(_ error: Error) {
        do {
            throw error
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            session = nil
            sessionInstructions = ""
            needsContextPrefix = false
        } catch {
            // Keep the session for rateLimited / guardrail / refusal / concurrent.
        }
    }

    /// Maps an error thrown by a turn to a short, human line for the chat UI.
    func friendlyErrorMessage(for error: Error) -> String {
        if case IRISError.busy = error {
            return "I'm still finishing my last reply — give me a second."
        }
        if #available(iOS 26.0, *) {
            return Self.mapGenerationError(error)
        }
        return "IRIS hit a snag. Try again?"
    }

    @available(iOS 26.0, *)
    private static func mapGenerationError(_ error: Error) -> String {
        do {
            throw error
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return "This conversation got long, so I trimmed some context. Try that again?"
        } catch LanguageModelSession.GenerationError.rateLimited {
            return "I'm catching my breath — give me a moment and try again."
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            return "I can't help with that one. Want to try rephrasing?"
        } catch LanguageModelSession.GenerationError.refusal {
            return "I'm not able to answer that. Ask me something else?"
        } catch LanguageModelSession.GenerationError.concurrentRequests {
            return "I'm still finishing my last reply — give me a second."
        } catch {
            return "IRIS hit a snag. Try again?"
        }
    }

    // MARK: - Session lifecycle

    @available(iOS 26.0, *)
    private func activeSession() -> LanguageModelSession {
        let currentInstructions = IRISPersonality.instructionsForCurrentUser()
        if let existing = session as? LanguageModelSession, sessionInstructions == currentInstructions {
            return existing
        }
        let newSession = LanguageModelSession(
            tools: IRISAgentService.tools,
            instructions: currentInstructions
        )
        session = newSession
        sessionInstructions = currentInstructions
        needsContextPrefix = true   // ground the first turn of this fresh session
        return newSession
    }

    /// The tools IRIS can call. Computed (gated) so the FoundationModels
    /// `Tool` types are only referenced on iOS 26+.
    @available(iOS 26.0, *)
    private static var tools: [any Tool] {
        [
            GetTripsTool(),
            GetWeatherTool(),
            GetVisaAndEssentialsTool(),
            RememberPreferenceTool(),
            GetDepartureRecommendationTool(),
            SubmitExpensesTool(),
            GetTravelProfileTool(),
            NavigateTool(),
            LogExpenseTool(),
            AddTripTool(),
            CheckInTool(),
            GeneratePackingListTool(),
            FlightActionsTool(),
            // Integration bridge tools (IRISIntegrationTools.swift) — connect
            // IRIS to services she previously couldn't reach.
            ConvertCurrencyTool(),
            GetFlightStatusTool(),
            SearchRentalCarsTool(),
            DisruptionTool(),
            TraceBaggageTool(),
            AddToCalendarTool()
        ]
    }
}

// MARK: - Errors

enum IRISError: LocalizedError {
    case unavailable
    case busy

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "IRIS is unavailable on this device."
        case .busy:
            return "IRIS is still finishing her last reply."
        }
    }
}
