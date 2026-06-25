package com.jetsetter.pro.core.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.jetsetter.pro.core.model.ThemePreference
import com.jetsetter.pro.core.model.UserPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore by preferencesDataStore(name = "user_prefs")

/** Persists user settings via Jetpack DataStore (replaces the iOS `UserPreferences`/UserDefaults). */
@Singleton
class UserPreferencesRepository @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private object Keys {
        val displayName = stringPreferencesKey("display_name")
        val homeAirport = stringPreferencesKey("home_airport")
        val theme = stringPreferencesKey("theme")
    }

    val preferences: Flow<UserPreferences> = context.dataStore.data.map { prefs ->
        UserPreferences(
            displayName = prefs[Keys.displayName] ?: "",
            homeAirport = prefs[Keys.homeAirport] ?: "",
            theme = runCatching { ThemePreference.valueOf(prefs[Keys.theme] ?: ThemePreference.SYSTEM.name) }
                .getOrDefault(ThemePreference.SYSTEM),
        )
    }

    suspend fun setDisplayName(value: String) = context.dataStore.edit { it[Keys.displayName] = value }
    suspend fun setHomeAirport(value: String) = context.dataStore.edit { it[Keys.homeAirport] = value }
    suspend fun setTheme(value: ThemePreference) = context.dataStore.edit { it[Keys.theme] = value.name }
}
