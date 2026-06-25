package com.jetsetter.pro.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.jetsetter.pro.ui.theme.JetTheme

/** Accent capsule tag — Android counterpart of the iOS `GoldTag`. */
@Composable
fun AccentTag(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
) {
    val colors = JetTheme.colors
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(colors.accent.copy(alpha = 0.15f))
            .border(0.5.dp, colors.accent.copy(alpha = 0.30f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = colors.accent, modifier = Modifier.size(12.dp))
        }
        Text(text, style = JetTheme.typography.label, color = colors.accent)
    }
}
