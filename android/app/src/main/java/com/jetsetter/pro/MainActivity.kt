package com.jetsetter.pro

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.jetsetter.pro.core.model.ThemePreference
import com.jetsetter.pro.feature.more.SettingsViewModel
import com.jetsetter.pro.ui.JetSetterApp
import com.jetsetter.pro.ui.theme.JetSetterTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            // Resolve the active theme from the user's saved preference (defaults to system).
            val settingsViewModel: SettingsViewModel = hiltViewModel()
            val prefs by settingsViewModel.preferences.collectAsStateWithLifecycle()
            val darkTheme = when (prefs.theme) {
                ThemePreference.DARK -> true
                ThemePreference.LIGHT -> false
                ThemePreference.SYSTEM -> isSystemInDarkTheme()
            }
            JetSetterTheme(darkTheme = darkTheme) {
                JetSetterApp()
            }
        }
    }
}
