package com.jetsetter.pro.feature.itinerary

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.jetsetter.pro.core.data.repository.TripRepository
import com.jetsetter.pro.core.model.PackingItem
import com.jetsetter.pro.core.model.Trip
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ItineraryViewModel @Inject constructor(
    private val tripRepository: TripRepository,
) : ViewModel() {

    init {
        viewModelScope.launch { tripRepository.seedIfEmpty() }
    }

    val trips: StateFlow<List<Trip>> =
        tripRepository.observeTrips()
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun togglePacked(trip: Trip, item: PackingItem) {
        val updated = trip.copy(
            packingList = trip.packingList.map {
                if (it.id == item.id) it.copy(isPacked = !it.isPacked) else it
            },
        )
        viewModelScope.launch { tripRepository.upsert(updated) }
    }

    fun addSampleTrip() {
        viewModelScope.launch {
            tripRepository.upsert(
                Trip(
                    name = "New Trip",
                    destination = "TBD",
                    startDate = "2026-12-01",
                    endDate = "2026-12-05",
                ),
            )
        }
    }
}
