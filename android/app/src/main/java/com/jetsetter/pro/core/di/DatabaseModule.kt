package com.jetsetter.pro.core.di

import android.content.Context
import androidx.room.Room
import com.jetsetter.pro.core.data.local.JetSetterDatabase
import com.jetsetter.pro.core.data.local.TripDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): JetSetterDatabase =
        Room.databaseBuilder(context, JetSetterDatabase::class.java, "jetsetter.db")
            .fallbackToDestructiveMigration()
            .build()

    @Provides
    fun provideTripDao(db: JetSetterDatabase): TripDao = db.tripDao()
}
