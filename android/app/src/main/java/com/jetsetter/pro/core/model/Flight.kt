package com.jetsetter.pro.core.model

/** Airport reference (subset of the iOS `FlightModel.Airport`). */
data class Airport(
    val code: String,         // IATA, e.g. "LAS"
    val city: String,
    val name: String? = null,
)

/** Flight status snapshot (subset of the iOS `FlightModel.Flight`). */
data class Flight(
    val ident: String,            // e.g. "DL1423"
    val operatorName: String?,    // e.g. "Delta Air Lines"
    val origin: Airport,
    val destination: Airport,
    val status: String,           // "On Time", "Delayed", "Cancelled"
    val scheduledOut: String,     // ISO-8601
    val scheduledIn: String,
    val gateOrigin: String? = null,
    val terminalOrigin: String? = null,
    val progressPercent: Int = 0,
)
