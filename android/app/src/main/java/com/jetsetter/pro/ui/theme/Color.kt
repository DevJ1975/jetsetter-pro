package com.jetsetter.pro.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Raw brand palette — hex values ported 1:1 from the iOS design system
 * (`JetSetter Pro/UI/Theme/JetsetterTheme.swift`). Each token has a dark and a
 * light value; the active set is chosen in [JetSetterTheme].
 */
internal object Palette {
    // Backgrounds
    val BackgroundDark = Color(0xFF10131E)
    val BackgroundLight = Color(0xFFEFF1F8)
    val SurfaceDark = Color(0xFF161929)
    val SurfaceLight = Color(0xFFFFFFFF)
    val SurfaceElevatedDark = Color(0xFF1D2235)
    val SurfaceElevatedLight = Color(0xFFF4F5FB)

    // Brand
    val PrimaryDark = Color(0xFF1C3555)
    val PrimaryLight = Color(0xFF0A2040)
    val AccentDark = Color(0xFF3B9EF0)
    val AccentLight = Color(0xFF0055CC)
    val BlueDark = Color(0xFF4E8FD4)
    val BlueLight = Color(0xFF1A5FA8)

    // Status
    val SuccessDark = Color(0xFF1DB97D)
    val SuccessLight = Color(0xFF0C7A4E)
    val WarningDark = Color(0xFFE8A020)
    val WarningLight = Color(0xFFB07010)
    val DangerDark = Color(0xFFE84040)
    val DangerLight = Color(0xFFC42020)

    // Text
    val TextPrimaryDark = Color(0xFFECEEF4)
    val TextPrimaryLight = Color(0xFF0A0C18)
    val TextSecondaryDark = Color(0xFF8B92A8)
    val TextSecondaryLight = Color(0xFF52587A)

    // Borders / separators
    val SeparatorDark = Color(0xFF1E2136)
    val SeparatorLight = Color(0xFFDDE0EE)
}
