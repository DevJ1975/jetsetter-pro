package com.jetsetter.pro.feature.itinerary

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.jetsetter.pro.core.model.ItineraryItem
import com.jetsetter.pro.core.model.PackingItem
import com.jetsetter.pro.core.model.Trip
import com.jetsetter.pro.ui.components.JetCard
import com.jetsetter.pro.ui.theme.JetTheme

@Composable
fun ItineraryScreen(viewModel: ItineraryViewModel = hiltViewModel()) {
    val trips by viewModel.trips.collectAsStateWithLifecycle()
    val colors = JetTheme.colors
    val spacing = JetTheme.spacing

    Box(modifier = Modifier.fillMaxSize().background(colors.background)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(
                start = spacing.medium,
                end = spacing.medium,
                top = spacing.large,
                bottom = 96.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(spacing.medium),
        ) {
            item {
                Text("Itinerary", style = JetTheme.typography.displayTitle, color = colors.textPrimary)
            }
            if (trips.isEmpty()) {
                item { EmptyState() }
            } else {
                items(trips, key = { it.id }) { trip ->
                    TripCard(trip = trip, onTogglePacked = { item -> viewModel.togglePacked(trip, item) })
                }
            }
        }
        FloatingActionButton(
            onClick = { viewModel.addSampleTrip() },
            containerColor = colors.accent,
            contentColor = Color.White,
            modifier = Modifier.align(Alignment.BottomEnd).padding(spacing.medium),
        ) {
            Icon(Icons.Filled.Add, contentDescription = "Add trip")
        }
    }
}

@Composable
private fun TripCard(trip: Trip, onTogglePacked: (PackingItem) -> Unit) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    JetCard(modifier = Modifier.fillMaxWidth()) {
        Text(trip.name, style = typography.cardTitle, color = colors.textPrimary)
        Text(
            "${trip.destination} · ${trip.startDate} → ${trip.endDate}",
            style = typography.caption,
            color = colors.textSecondary,
        )
        Spacer(Modifier.height(12.dp))
        trip.sortedItems.forEach { item -> ItineraryRow(item) }
        if (trip.packingList.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Text("PACKING", style = typography.caption, color = colors.textSecondary)
            Spacer(Modifier.height(4.dp))
            trip.packingList.forEach { packingItem ->
                PackingRow(packingItem, onToggle = { onTogglePacked(packingItem) })
            }
        }
    }
}

@Composable
private fun ItineraryRow(item: ItineraryItem) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(modifier = Modifier.size(10.dp).clip(CircleShape).background(Color(item.type.colorHex)))
        Column(modifier = Modifier.weight(1f)) {
            Text(item.title, style = typography.bodyMedium, color = colors.textPrimary)
            val location = item.location
            if (location != null) {
                Text(location, style = typography.caption, color = colors.textSecondary)
            }
        }
        Text(item.type.label, style = typography.caption, color = colors.textSecondary)
    }
}

@Composable
private fun PackingRow(item: PackingItem, onToggle: () -> Unit) {
    val colors = JetTheme.colors
    val typography = JetTheme.typography
    Row(
        modifier = Modifier.fillMaxWidth().clickable { onToggle() }.padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = if (item.isPacked) Icons.Filled.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (item.isPacked) colors.success else colors.textSecondary,
            modifier = Modifier.size(20.dp),
        )
        Text(
            item.name,
            style = typography.bodyMedium,
            color = if (item.isPacked) colors.textSecondary else colors.textPrimary,
        )
    }
}

@Composable
private fun EmptyState() {
    val colors = JetTheme.colors
    JetCard(modifier = Modifier.fillMaxWidth()) {
        Text("No trips yet", style = JetTheme.typography.cardTitle, color = colors.textPrimary)
        Spacer(Modifier.height(4.dp))
        Text("Tap + to add your first trip.", style = JetTheme.typography.bodyMedium, color = colors.textSecondary)
    }
}
