package com.jetsetter.pro.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** Semantic colors for the JetSetter design system (parallels iOS `JetsetterTheme.Colors`). */
@Immutable
data class JetColors(
    val background: Color,
    val surface: Color,
    val surfaceElevated: Color,
    val primary: Color,
    val accent: Color,
    val blue: Color,
    val success: Color,
    val warning: Color,
    val danger: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val separator: Color,
    val isDark: Boolean,
)

private val DarkJetColors = JetColors(
    background = Palette.BackgroundDark,
    surface = Palette.SurfaceDark,
    surfaceElevated = Palette.SurfaceElevatedDark,
    primary = Palette.PrimaryDark,
    accent = Palette.AccentDark,
    blue = Palette.BlueDark,
    success = Palette.SuccessDark,
    warning = Palette.WarningDark,
    danger = Palette.DangerDark,
    textPrimary = Palette.TextPrimaryDark,
    textSecondary = Palette.TextSecondaryDark,
    separator = Palette.SeparatorDark,
    isDark = true,
)

private val LightJetColors = JetColors(
    background = Palette.BackgroundLight,
    surface = Palette.SurfaceLight,
    surfaceElevated = Palette.SurfaceElevatedLight,
    primary = Palette.PrimaryLight,
    accent = Palette.AccentLight,
    blue = Palette.BlueLight,
    success = Palette.SuccessLight,
    warning = Palette.WarningLight,
    danger = Palette.DangerLight,
    textPrimary = Palette.TextPrimaryLight,
    textSecondary = Palette.TextSecondaryLight,
    separator = Palette.SeparatorLight,
    isDark = false,
)

val LocalJetColors = staticCompositionLocalOf { DarkJetColors }

/**
 * Root theme. Provides the JetSetter semantic colors / typography / spacing and a
 * mapped Material 3 [MaterialTheme] so stock M3 components also pick up the brand.
 * Defaults to the system setting; the app overrides this from the user's saved
 * preference (see `MainActivity`). iOS default is dark — that carries over here.
 */
@Composable
fun JetSetterTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val jetColors = if (darkTheme) DarkJetColors else LightJetColors
    val material = if (darkTheme) {
        darkColorScheme(
            primary = jetColors.accent,
            onPrimary = Color.White,
            background = jetColors.background,
            onBackground = jetColors.textPrimary,
            surface = jetColors.surface,
            onSurface = jetColors.textPrimary,
            error = jetColors.danger,
        )
    } else {
        lightColorScheme(
            primary = jetColors.accent,
            onPrimary = Color.White,
            background = jetColors.background,
            onBackground = jetColors.textPrimary,
            surface = jetColors.surface,
            onSurface = jetColors.textPrimary,
            error = jetColors.danger,
        )
    }

    CompositionLocalProvider(
        LocalJetColors provides jetColors,
        LocalJetTypography provides JetTypography(),
        LocalJetSpacing provides JetSpacing(),
    ) {
        MaterialTheme(
            colorScheme = material,
            typography = JetMaterialTypography,
            shapes = JetShapes,
            content = content,
        )
    }
}

/** Accessor object mirroring `MaterialTheme`: `JetTheme.colors`, `JetTheme.typography`, `JetTheme.spacing`. */
object JetTheme {
    val colors: JetColors
        @Composable @ReadOnlyComposable get() = LocalJetColors.current
    val typography: JetTypography
        @Composable @ReadOnlyComposable get() = LocalJetTypography.current
    val spacing: JetSpacing
        @Composable @ReadOnlyComposable get() = LocalJetSpacing.current
}
