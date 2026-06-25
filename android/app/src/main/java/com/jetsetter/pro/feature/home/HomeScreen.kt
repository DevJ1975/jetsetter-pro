package com.jetsetter.pro.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.FlightTakeoff
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Wallet
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.jetsetter.pro.core.model.Flight
import com.jetsetter.pro.ui.components.AccentTag
import com.jetsetter.pro.ui.components.JetCard
import com.jetsetter.pro.ui.theme.JetTheme

@Composable
fun HomeScreen(viewModel: HomeViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
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
        HomeHeader()
        NextFlightCard(state.nextFlight)
        QuickActionsRow()
        TravelIntelligenceCard(state.upcomingTrip?.destination)
    }
}

@Composable
private fun HomeHeader() {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    Column {
        Text("Good morning", style = typography.bodyMedium, color = colors.textSecondary)
        Text("Welcome aboard", style = typography.displayTitle, color = colors.textPrimary)
    }
}

@Composable
private fun NextFlightCard(flight: Flight) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    JetCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.FlightTakeoff, contentDescription = null, tint = colors.accent)
                Text(flight.ident, style = typography.cardTitle, color = colors.textPrimary)
            }
            AccentTag(text = flight.status, icon = Icons.Filled.Schedule)
        }
        Spacer(Modifier.height(16.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AirportColumn(flight.origin.code, flight.origin.city, alignEnd = false)
            Icon(Icons.Filled.Flight, contentDescription = null, tint = colors.textSecondary)
            AirportColumn(flight.destination.code, flight.destination.city, alignEnd = true)
        }
        Spacer(Modifier.height(16.dp))
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            InfoPair("Gate", flight.gateOrigin ?: "—")
            InfoPair("Terminal", flight.terminalOrigin ?: "—")
            InfoPair("Airline", flight.operatorName ?: "—")
        }
    }
}

@Composable
private fun AirportColumn(code: String, city: String, alignEnd: Boolean) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    Column(horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
        Text(code, style = typography.metric, color = colors.textPrimary)
        Text(city, style = typography.caption, color = colors.textSecondary)
    }
}

@Composable
private fun InfoPair(label: String, value: String) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    Column {
        Text(label.uppercase(), style = typography.caption, color = colors.textSecondary)
        Text(value, style = typography.cardTitle, color = colors.textPrimary)
    }
}

@Composable
private fun QuickActionsRow() {
    val actions = listOf(
        "Check-In" to Icons.Filled.HowToReg,
        "Disruptions" to Icons.Filled.Warning,
        "Expenses" to Icons.Filled.ReceiptLong,
        "Wallet" to Icons.Filled.Wallet,
    )
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        actions.forEach { (label, icon) ->
            QuickAction(label, icon, Modifier.weight(1f))
        }
    }
}

@Composable
private fun QuickAction(label: String, icon: ImageVector, modifier: Modifier = Modifier) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(colors.surface)
            .border(0.6.dp, colors.separator, RoundedCornerShape(16.dp))
            .padding(vertical = 14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, contentDescription = null, tint = colors.accent)
        Text(label, style = typography.caption, color = colors.textSecondary)
    }
}

@Composable
private fun TravelIntelligenceCard(destination: String?) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    JetCard(modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = colors.accent)
            Text("Travel Intelligence", style = typography.cardTitle, color = colors.textPrimary)
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = if (destination != null) {
                "Your next trip is to $destination. IRIS will watch your flights and flag disruptions automatically."
            } else {
                "Add a trip and IRIS will start watching your flights, weather, and expenses."
            },
            style = typography.bodyMedium,
            color = colors.textSecondary,
        )
    }
}
