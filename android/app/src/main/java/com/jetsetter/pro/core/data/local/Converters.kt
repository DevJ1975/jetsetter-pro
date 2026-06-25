package com.jetsetter.pro.core.data.local

import androidx.room.TypeConverter
import com.jetsetter.pro.core.model.ItineraryItem
import com.jetsetter.pro.core.model.PackingItem
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

/**
 * Room type converters. Trips store their nested item/packing lists as JSON, mirroring
 * the iOS approach of encoding `[ItineraryItem]` / `[PackingItem]` into a single field.
 * Room instantiates this class with a no-arg constructor, so Moshi lives here as a field.
 */
class Converters {
    private val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()

    private val itemsType = Types.newParameterizedType(List::class.java, ItineraryItem::class.java)
    private val packingType = Types.newParameterizedType(List::class.java, PackingItem::class.java)
    private val itemsAdapter = moshi.adapter<List<ItineraryItem>>(itemsType)
    private val packingAdapter = moshi.adapter<List<PackingItem>>(packingType)

    @TypeConverter
    fun itemsToJson(value: List<ItineraryItem>): String = itemsAdapter.toJson(value)

    @TypeConverter
    fun jsonToItems(json: String): List<ItineraryItem> = itemsAdapter.fromJson(json) ?: emptyList()

    @TypeConverter
    fun packingToJson(value: List<PackingItem>): String = packingAdapter.toJson(value)

    @TypeConverter
    fun jsonToPacking(json: String): List<PackingItem> = packingAdapter.fromJson(json) ?: emptyList()
}
