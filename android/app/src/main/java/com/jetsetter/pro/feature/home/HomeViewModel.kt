package com.jetsetter.pro.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.jetsetter.pro.core.data.mock.MockData
import com.jetsetter.pro.core.data.repository.TripRepository
import com.jetsetter.pro.core.model.Flight
import com.jetsetter.pro.core.model.Trip
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class HomeUiState(
    val nextFlight: Flight = MockData.nextFlight,
    val upcomingTrip: Trip? = null,
)

@HiltViewModel
class HomeViewModel @Inject constructor(
    tripRepository: TripRepository,
) : ViewModel() {

    init {
        viewModelScope.launch { tripRepository.seedIfEmpty() }
    }

    val uiState: StateFlow<HomeUiState> =
        tripRepository.observeTrips()
            .map { trips -> HomeUiState(nextFlight = MockData.nextFlight, upcomingTrip = trips.firstOrNull()) }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeUiState())
}
