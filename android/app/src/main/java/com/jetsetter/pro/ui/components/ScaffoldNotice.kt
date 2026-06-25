package com.jetsetter.pro.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.jetsetter.pro.ui.theme.JetTheme

/** Small inline banner marking a feature that is stubbed in this scaffold. */
@Composable
fun ScaffoldNotice(text: String, modifier: Modifier = Modifier) {
    val colors = JetTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.warning.copy(alpha = 0.12f))
            .border(0.5.dp, colors.warning.copy(alpha = 0.30f), shape)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            Icons.Filled.Construction,
            contentDescription = null,
            tint = colors.warning,
            modifier = Modifier.size(18.dp),
        )
        Text(text, style = JetTheme.typography.caption, color = colors.textSecondary)
    }
}
