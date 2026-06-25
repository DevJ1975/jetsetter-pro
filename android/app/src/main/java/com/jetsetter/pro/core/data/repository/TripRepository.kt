package com.jetsetter.pro.core.data.repository

import com.jetsetter.pro.core.data.local.TripDao
import com.jetsetter.pro.core.data.local.toDomain
import com.jetsetter.pro.core.data.local.toEntity
import com.jetsetter.pro.core.data.mock.MockData
import com.jetsetter.pro.core.model.Trip
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Single source of truth for trips. Backed by Room; seeds [MockData] on first run so the
 * app is usable offline / without API keys. (Firebase Firestore sync is a documented
 * next step — see docs/API_REFERENCE.md.)
 */
@Singleton
class TripRepository @Inject constructor(
    private val tripDao: TripDao,
) {
    fun observeTrips(): Flow<List<Trip>> =
        tripDao.observeAll().map { entities -> entities.map { it.toDomain() } }

    suspend fun seedIfEmpty() {
        if (tripDao.count() == 0) {
            tripDao.upsertAll(MockData.trips.map { it.toEntity() })
        }
    }

    suspend fun upsert(trip: Trip) = tripDao.upsert(trip.toEntity())

    suspend fun delete(id: String) = tripDao.delete(id)
}
