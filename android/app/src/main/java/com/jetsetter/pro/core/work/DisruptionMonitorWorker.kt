package com.jetsetter.pro.core.work

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * Background flight-disruption monitor — the Android counterpart of the iOS
 * `DisruptionMonitorService` (which used BGTaskScheduler). This is a stub: schedule it as
 * a `PeriodicWorkRequest` once the Flight Tracker / Disruption features are ported. For
 * dependency-injected workers, migrate to `@HiltWorker` + `androidx.hilt:hilt-work`.
 *
 * See docs/FEATURE_PARITY.md → Disruption.
 */
class DisruptionMonitorWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        // TODO: poll FlightAware for tracked flights, detect cancellation / >45min delay /
        //  gate change / missed connection, and raise notifications.
        return Result.success()
    }

    companion object {
        const val UNIQUE_NAME = "disruption_monitor"
    }
}
