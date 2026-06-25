package com.jetsetter.pro.core.secrets

import com.jetsetter.pro.BuildConfig

/**
 * Centralized access to API keys — the Android counterpart of the iOS `AppSecrets`.
 *
 * Keys are injected at build time from `local.properties` (or the environment) into
 * `BuildConfig` (see app/build.gradle.kts). A key is considered *not configured* if it
 * is blank or still a placeholder (`YOUR_…`, `REPLACE_ME`). Callers should fall back to
 * mock data when [isConfigured] is false — exactly as the iOS app does.
 */
object Secrets {
    val flightAware: String get() = BuildConfig.API_FLIGHTAWARE
    val anthropic: String get() = BuildConfig.API_ANTHROPIC
    val googleVision: String get() = BuildConfig.API_GOOGLE_VISION
    val firebaseProjectId: String get() = BuildConfig.API_FIREBASE_PROJECT_ID
    val firebaseApiKey: String get() = BuildConfig.API_FIREBASE_API_KEY
    val uberServerToken: String get() = BuildConfig.API_UBER_SERVER_TOKEN
    val sitaWorldTracer: String get() = BuildConfig.API_SITA_WORLDTRACER

    /** True when [value] is a real, usable key (non-blank and not a placeholder). */
    fun isConfigured(value: String): Boolean {
        val v = value.trim()
        return v.isNotEmpty() &&
            !v.startsWith("YOUR_", ignoreCase = true) &&
            !v.equals("REPLACE_ME", ignoreCase = true)
    }
}
