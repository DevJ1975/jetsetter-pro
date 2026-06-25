package com.jetsetter.pro.core.di

import com.jetsetter.pro.BuildConfig
import com.jetsetter.pro.core.data.remote.ClaudeApi
import com.jetsetter.pro.core.data.remote.FlightAwareApi
import com.jetsetter.pro.core.data.remote.RetryInterceptor
import com.jetsetter.pro.core.secrets.Secrets
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import javax.inject.Named
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideMoshi(): Moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()

    @Provides
    @Singleton
    fun provideLogging(): HttpLoggingInterceptor = HttpLoggingInterceptor().apply {
        level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.BASIC else HttpLoggingInterceptor.Level.NONE
    }

    // ── FlightAware AeroAPI ──────────────────────────────────────────────────
    @Provides
    @Singleton
    @Named("flightaware")
    fun provideFlightAwareRetrofit(moshi: Moshi, logging: HttpLoggingInterceptor): Retrofit {
        val client = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .addHeader("x-apikey", Secrets.flightAware)
                    .build()
                chain.proceed(request)
            }
            .addInterceptor(RetryInterceptor())
            .addInterceptor(logging)
            .build()
        return Retrofit.Builder()
            .baseUrl("https://aeroapi.flightaware.com/aeroapi/")
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
    }

    @Provides
    @Singleton
    fun provideFlightAwareApi(@Named("flightaware") retrofit: Retrofit): FlightAwareApi =
        retrofit.create(FlightAwareApi::class.java)

    // ── Anthropic Claude (IRIS) ──────────────────────────────────────────────
    @Provides
    @Singleton
    @Named("anthropic")
    fun provideClaudeRetrofit(moshi: Moshi, logging: HttpLoggingInterceptor): Retrofit {
        val client = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .addHeader("x-api-key", Secrets.anthropic)
                    .addHeader("anthropic-version", "2023-06-01")
                    .addHeader("content-type", "application/json")
                    .build()
                chain.proceed(request)
            }
            .addInterceptor(logging)
            .build()
        return Retrofit.Builder()
            .baseUrl("https://api.anthropic.com/")
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
    }

    @Provides
    @Singleton
    fun provideClaudeApi(@Named("anthropic") retrofit: Retrofit): ClaudeApi =
        retrofit.create(ClaudeApi::class.java)
}
