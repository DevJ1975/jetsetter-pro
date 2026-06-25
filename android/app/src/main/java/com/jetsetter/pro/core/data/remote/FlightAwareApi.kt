package com.jetsetter.pro.core.data.remote

import retrofit2.http.GET
import retrofit2.http.Path

/**
 * FlightAware AeroAPI — flight status by identifier. The `x-apikey` header is attached
 * by an interceptor in `NetworkModule`. DTOs here are a minimal slice; expand them as the
 * Flight Tracker feature is ported (see docs/API_REFERENCE.md).
 */
interface FlightAwareApi {
    @GET("flights/{ident}")
    suspend fun getFlight(@Path("ident") ident: String): FlightAwareResponse
}

data class FlightAwareResponse(
    val flights: List<FlightAwareFlight> = emptyList(),
)

data class FlightAwareFlight(
    val ident: String?,
    val operator: String?,
    val status: String?,
)
