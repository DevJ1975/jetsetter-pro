package com.jetsetter.pro.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.jetsetter.pro.ui.theme.JetTheme

/** Rounded input field — Android counterpart of the iOS `.premiumInput()` style. */
@Composable
fun PremiumTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    singleLine: Boolean = true,
) {
    val colors = JetTheme.colors
    val shape = RoundedCornerShape(12.dp)
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = singleLine,
        textStyle = JetTheme.typography.bodyMedium.copy(color = colors.textPrimary),
        cursorBrush = SolidColor(colors.accent),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
        modifier = modifier
            .clip(shape)
            .background(if (colors.isDark) Color(0xFF141726) else Color(0xFFF4F5FB))
            .border(0.5.dp, colors.accent.copy(alpha = if (colors.isDark) 0.18f else 0.06f), shape)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        decorationBox = { inner ->
            if (value.isEmpty() && placeholder.isNotEmpty()) {
                Text(placeholder, style = JetTheme.typography.bodyMedium, color = colors.textSecondary)
            }
            inner()
        },
    )
}
