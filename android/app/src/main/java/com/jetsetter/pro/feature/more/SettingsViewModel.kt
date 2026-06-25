package com.jetsetter.pro.feature.more

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.jetsetter.pro.core.data.prefs.UserPreferencesRepository
import com.jetsetter.pro.core.model.ThemePreference
import com.jetsetter.pro.core.model.UserPreferences
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val prefsRepository: UserPreferencesRepository,
) : ViewModel() {

    val preferences: StateFlow<UserPreferences> =
        prefsRepository.preferences
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UserPreferences())

    fun setTheme(theme: ThemePreference) = viewModelScope.launch { prefsRepository.setTheme(theme) }
    fun setDisplayName(value: String) = viewModelScope.launch { prefsRepository.setDisplayName(value) }
    fun setHomeAirport(value: String) = viewModelScope.launch { prefsRepository.setHomeAirport(value) }
}
