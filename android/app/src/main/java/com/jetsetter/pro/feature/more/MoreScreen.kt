package com.jetsetter.pro.feature.more

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.jetsetter.pro.core.model.ThemePreference
import com.jetsetter.pro.ui.components.JetCard
import com.jetsetter.pro.ui.components.PremiumTextField
import com.jetsetter.pro.ui.components.ScaffoldNotice
import com.jetsetter.pro.ui.theme.JetTheme

@Composable
fun MoreScreen(viewModel: SettingsViewModel = hiltViewModel()) {
    val prefs by viewModel.preferences.collectAsStateWithLifecycle()
    val colors = JetTheme.colors
    val spacing = JetTheme.spacing

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(horizontal = spacing.medium)
            .padding(top = spacing.large, bottom = spacing.xlarge),
        verticalArrangement = Arrangement.spacedBy(spacing.medium),
    ) {
        Text("More", style = JetTheme.typography.displayTitle, color = colors.textPrimary)

        JetCard(modifier = Modifier.fillMaxWidth()) {
            Text("Appearance", style = JetTheme.typography.cardTitle, color = colors.textPrimary)
            Spacer(Modifier.height(12.dp))
            ThemeSelector(selected = prefs.theme, onSelect = { viewModel.setTheme(it) })
        }

        JetCard(modifier = Modifier.fillMaxWidth()) {
            Text("Profile", style = JetTheme.typography.cardTitle, color = colors.textPrimary)
            Spacer(Modifier.height(12.dp))
            LabeledField("Display name", prefs.displayName, "Your name") { viewModel.setDisplayName(it) }
            Spacer(Modifier.height(10.dp))
            LabeledField("Home airport", prefs.homeAirport, "e.g. LAS") { viewModel.setHomeAirport(it) }
        }

        ScaffoldNotice(
            "Subscriptions, account sync, the document/identity/loyalty vaults, and the other ~30 " +
                "modules are tracked in docs/FEATURE_PARITY.md.",
        )

        JetCard(modifier = Modifier.fillMaxWidth()) {
            Text("About", style = JetTheme.typography.cardTitle, color = colors.textPrimary)
            Spacer(Modifier.height(6.dp))
            Text("JetSetter Pro for Android · v0.1.0", style = JetTheme.typography.bodyMedium, color = colors.textSecondary)
            Text("Trainovate Technologies LLC", style = JetTheme.typography.caption, color = colors.textSecondary)
        }
    }
}

@Composable
private fun ThemeSelector(selected: ThemePreference, onSelect: (ThemePreference) -> Unit) {
    val colors = JetTheme.colors
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ThemePreference.entries.forEach { option ->
            val isSelected = option == selected
            Text(
                text = option.name.lowercase().replaceFirstChar { it.uppercase() },
                style = JetTheme.typography.label,
                color = if (isSelected) Color.White else colors.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isSelected) colors.accent else colors.surfaceElevated)
                    .clickable { onSelect(option) }
                    .padding(vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun LabeledField(
    label: String,
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
) {
    val colors = JetTheme.colors
    Column {
        Text(label.uppercase(), style = JetTheme.typography.caption, color = colors.textSecondary)
        Spacer(Modifier.height(4.dp))
        PremiumTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = placeholder,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
