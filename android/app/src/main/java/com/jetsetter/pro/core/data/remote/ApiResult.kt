package com.jetsetter.pro.core.data.remote

/** Lightweight result wrapper for network calls. */
sealed interface ApiResult<out T> {
    data class Success<T>(val data: T) : ApiResult<T>
    data class Failure(val error: ApiError) : ApiResult<Nothing>
}

/** Typed network errors — parallels the iOS `APIError` enum. */
sealed class ApiError(message: String? = null, cause: Throwable? = null) : Exception(message, cause) {
    data object InvalidUrl : ApiError("Invalid URL")
    data object Unauthorized : ApiError("Unauthorized (401)")
    data class RateLimited(val retryAfterSeconds: Long?) : ApiError("Rate limited (429)")
    data class RequestFailed(val statusCode: Int) : ApiError("Request failed ($statusCode)")
    data class DecodingFailed(val throwable: Throwable) : ApiError("Decoding failed", throwable)
    data class Unknown(val throwable: Throwable) : ApiError("Unknown error", throwable)
}
