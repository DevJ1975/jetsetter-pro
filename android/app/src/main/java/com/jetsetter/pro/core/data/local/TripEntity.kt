package com.jetsetter.pro.core.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.jetsetter.pro.core.model.ItineraryItem
import com.jetsetter.pro.core.model.PackingItem
import com.jetsetter.pro.core.model.Trip

@Entity(tableName = "trips")
data class TripEntity(
    @PrimaryKey val id: String,
    val name: String,
    val destination: String,
    val startDate: String,
    val endDate: String,
    val items: List<ItineraryItem>,
    val packingList: List<PackingItem>,
)

fun TripEntity.toDomain(): Trip =
    Trip(id, name, destination, startDate, endDate, items, packingList)

fun Trip.toEntity(): TripEntity =
    TripEntity(id, name, destination, startDate, endDate, items, packingList)
