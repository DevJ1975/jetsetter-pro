package com.jetsetter.pro.core.model

/** User-facing settings (subset of the iOS `UserPreferences`). Persisted via DataStore. */
data class UserPreferences(
    val displayName: String = "",
    val homeAirport: String = "",
    val theme: ThemePreference = ThemePreference.SYSTEM,
)

enum class ThemePreference { SYSTEM, LIGHT, DARK }
