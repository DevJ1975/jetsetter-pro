package com.jetsetter.pro.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.jetsetter.pro.ui.theme.JetGradients
import com.jetsetter.pro.ui.theme.JetTheme

/**
 * Glass card — the Android counterpart of the iOS `.jetCard()` modifier (CardStyle).
 * iOS uses `.ultraThinMaterial`; Compose has no backdrop blur, so we approximate with a
 * solid surface, an inner glow, a gradient border, and a soft shadow.
 */
@Composable
fun JetCard(
    modifier: Modifier = Modifier,
    contentPadding: Dp = 16.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = JetTheme.colors
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier = modifier
            .shadow(elevation = if (colors.isDark) 24.dp else 10.dp, shape = shape, clip = false)
            .clip(shape)
            .background(colors.surface, shape)
            .then(if (colors.isDark) Modifier.background(JetGradients.cardInnerGlow, shape) else Modifier)
            .border(
                width = 0.6.dp,
                brush = if (colors.isDark) JetGradients.accentBorder else SolidColor(Color.Black.copy(alpha = 0.06f)),
                shape = shape,
            )
            .padding(contentPadding),
        content = content,
    )
}
