package com.jetsetter.pro.core.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters

@Database(
    entities = [TripEntity::class],
    version = 1,
    exportSchema = false,
)
@TypeConverters(Converters::class)
abstract class JetSetterDatabase : RoomDatabase() {
    abstract fun tripDao(): TripDao
}
