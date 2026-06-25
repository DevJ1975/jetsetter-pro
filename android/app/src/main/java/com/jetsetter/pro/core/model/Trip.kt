package com.jetsetter.pro.core.model

import java.util.UUID

/** A multi-day trip with itinerary items and a packing list (iOS `ItineraryModel.Trip`). */
data class Trip(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val destination: String,
    val startDate: String,   // ISO-8601 date, e.g. "2026-07-14"
    val endDate: String,
    val items: List<ItineraryItem> = emptyList(),
    val packingList: List<PackingItem> = emptyList(),
) {
    val sortedItems: List<ItineraryItem> get() = items.sortedBy { it.startDate }
}

/** Itinerary item category. `colorHex` mirrors the per-type colors used on iOS. */
enum class ItineraryItemType(val label: String, val colorHex: Long) {
    FLIGHT("Flight", 0xFF0066CC),
    HOTEL("Hotel", 0xFF0A7A5E),
    ACTIVITY("Activity", 0xFFC8860A),
    TRANSPORT("Transport", 0xFF1A2E40),
    RESTAURANT("Restaurant", 0xFFCC3B1E),
}

data class ItineraryItem(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val type: ItineraryItemType,
    val startDate: String,        // ISO-8601 timestamp
    val endDate: String? = null,
    val location: String? = null,
    val notes: String? = null,
)

data class PackingItem(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val isPacked: Boolean = false,
)
