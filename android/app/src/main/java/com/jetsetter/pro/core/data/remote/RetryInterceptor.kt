package com.jetsetter.pro.core.data.remote

import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException

/**
 * Retries idempotent GETs a few times with capped exponential backoff — mirrors the
 * retry/backoff behavior of the iOS `APIClient`. POSTs are attempted once.
 */
class RetryInterceptor(
    private val maxGetRetries: Int = 3,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val maxAttempts = if (request.method.equals("GET", ignoreCase = true)) maxGetRetries else 1
        var attempt = 0
        var lastError: IOException? = null

        while (attempt < maxAttempts) {
            try {
                val response = chain.proceed(request)
                // Retry transient 503s on idempotent requests.
                if (response.code == 503 && attempt < maxAttempts - 1) {
                    response.close()
                    attempt++
                    sleepBackoff(attempt)
                    continue
                }
                return response
            } catch (e: IOException) {
                lastError = e
                attempt++
                if (attempt >= maxAttempts) break
                sleepBackoff(attempt)
            }
        }
        throw lastError ?: IOException("Request failed after $maxAttempts attempts")
    }

    private fun sleepBackoff(attempt: Int) {
        val millis = (1000L * (1 shl (attempt - 1))).coerceAtMost(10_000L)
        try {
            Thread.sleep(millis)
        } catch (ignored: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
}
