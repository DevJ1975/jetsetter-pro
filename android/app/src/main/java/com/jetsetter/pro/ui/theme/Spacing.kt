package com.jetsetter.pro.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Spacing scale ported from `JetsetterTheme.Spacing`. */
@Immutable
data class JetSpacing(
    val xsmall: Dp = 4.dp,
    val small: Dp = 8.dp,
    val medium: Dp = 16.dp,
    val large: Dp = 24.dp,
    val xlarge: Dp = 32.dp,
)

val LocalJetSpacing = staticCompositionLocalOf { JetSpacing() }
