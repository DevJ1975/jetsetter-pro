package com.jetsetter.pro.core.data.repository

import com.jetsetter.pro.core.data.remote.ClaudeApi
import com.jetsetter.pro.core.data.remote.ClaudeMessage
import com.jetsetter.pro.core.data.remote.ClaudeRequest
import com.jetsetter.pro.core.secrets.Secrets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Backs the IRIS assistant (Intelligent Routing & Itinerary Specialist).
 *
 * On iOS, IRIS routed Apple Intelligence (on-device) → Claude → canned demo. Android has
 * no on-device tier, so it standardizes on the Anthropic Claude API with a demo fallback
 * when no key is configured (matching the iOS demo responses).
 */
@Singleton
class IrisRepository @Inject constructor(
    private val claudeApi: ClaudeApi,
) {
    private val systemPrompt = """
        You are IRIS, JetSetter Pro's executive travel concierge. Be concise, proactive,
        and practical. Help with flights, itineraries, packing, expenses, and travel
        logistics. Prefer specific, actionable answers.
    """.trimIndent()

    /** [history] is the full conversation (user/assistant turns). Returns IRIS's reply. */
    suspend fun ask(history: List<ClaudeMessage>): String = withContext(Dispatchers.IO) {
        if (!Secrets.isConfigured(Secrets.anthropic)) {
            return@withContext demoResponse(history.lastOrNull { it.role == "user" }?.content.orEmpty())
        }
        // The Claude API requires the first message to be from the user.
        val trimmed = history.dropWhile { it.role != "user" }
        runCatching {
            claudeApi.createMessage(
                ClaudeRequest(
                    model = "claude-sonnet-4-6",
                    max_tokens = 600,
                    system = systemPrompt,
                    messages = trimmed,
                ),
            ).text
        }.getOrElse { e ->
            "I hit a snag reaching the travel network — ${e.message ?: "unknown error"}."
        }
    }

    private fun demoResponse(prompt: String): String = when {
        prompt.contains("delay", ignoreCase = true) ->
            "I'm watching DL 1423 to Atlanta — on time right now. I'll ping you the instant the gate or status changes."
        prompt.contains("pack", ignoreCase = true) ->
            "For your 3-day Atlanta trip: a suit, the printed board deck, laptop + charger, and your passport. Want a weather-based layer suggestion?"
        prompt.contains("expense", ignoreCase = true) ->
            "You're at \$1,812.75 across 4 items this trip. The Delta airfare (\$1,290) is the largest. Shall I export to Brex?"
        prompt.isBlank() ->
            "I'm IRIS, your travel concierge. Ask me about your flights, itinerary, packing, or expenses."
        else ->
            "I'm IRIS, your travel concierge. (Add an Anthropic API key in local.properties to enable live AI.) " +
                "Meanwhile: your next flight is DL 1423 LAS→ATL, on time, gate C22."
    }
}
