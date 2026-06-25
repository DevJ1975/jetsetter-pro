package com.jetsetter.pro.core.data.remote

import retrofit2.http.Body
import retrofit2.http.POST

/**
 * Anthropic Claude Messages API — backs the IRIS assistant.
 * The `x-api-key`, `anthropic-version`, and `content-type` headers are attached in
 * `NetworkModule`. See https://docs.anthropic.com/en/api/messages.
 */
interface ClaudeApi {
    @POST("v1/messages")
    suspend fun createMessage(@Body request: ClaudeRequest): ClaudeResponse
}

data class ClaudeRequest(
    val model: String,
    val max_tokens: Int,
    val system: String?,
    val messages: List<ClaudeMessage>,
)

data class ClaudeMessage(
    val role: String,   // "user" | "assistant"
    val content: String,
)

data class ClaudeResponse(
    val content: List<ClaudeContent> = emptyList(),
) {
    /** Convenience: the first text block of the response. */
    val text: String get() = content.firstOrNull { it.type == "text" }?.text.orEmpty()
}

data class ClaudeContent(
    val type: String,
    val text: String?,
)
