package com.jetsetter.pro.core.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface TripDao {

    @Query("SELECT * FROM trips ORDER BY startDate ASC")
    fun observeAll(): Flow<List<TripEntity>>

    @Query("SELECT COUNT(*) FROM trips")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(trip: TripEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(trips: List<TripEntity>)

    @Query("DELETE FROM trips WHERE id = :id")
    suspend fun delete(id: String)
}
