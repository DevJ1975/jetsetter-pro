package com.jetsetter.pro.ui.theme

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Brand gradients ported from `JetsetterTheme.Colors`. Note: the iOS gradient is
 * historically named `goldGradient` but actually renders as a blue accent shimmer —
 * the name is kept conceptually but the values are the real (blue) stops.
 */
object JetGradients {
    /** Accent shimmer — hero text, labels, logo (iOS `goldGradient`). */
    val accentShimmer = Brush.linearGradient(
        0.0f to Color(0xFF1A72E8),
        0.45f to Color(0xFF5BBAFF),
        0.75f to Color(0xFF3A9AF0),
        1.0f to Color(0xFF1A72E8),
        start = Offset(0f, 0f),
        end = Offset.Infinite,
    )

    /** Deep dark hero gradient — onboarding / splash backgrounds (iOS `heroGradient`). */
    val hero = Brush.linearGradient(
        0.0f to Color(0xFF06070D),
        0.5f to Color(0xFF0D1425),
        1.0f to Color(0xFF091530),
        start = Offset(0f, 0f),
        end = Offset.Infinite,
    )

    /** Subtle inner glow for cards in dark mode (iOS `cardInnerGlow`). */
    val cardInnerGlow = Brush.linearGradient(
        0.0f to Color.White.copy(alpha = 0.04f),
        1.0f to Color.Transparent,
        start = Offset(0f, 0f),
        end = Offset.Infinite,
    )

    /** Accent card border shimmer for dark mode (iOS `goldBorderGradient`). */
    val accentBorder = Brush.linearGradient(
        0.0f to Color(0xFF3B9EF0).copy(alpha = 0.30f),
        0.5f to Color.White.copy(alpha = 0.05f),
        1.0f to Color(0xFF3B9EF0).copy(alpha = 0.15f),
        start = Offset(0f, 0f),
        end = Offset.Infinite,
    )
}
