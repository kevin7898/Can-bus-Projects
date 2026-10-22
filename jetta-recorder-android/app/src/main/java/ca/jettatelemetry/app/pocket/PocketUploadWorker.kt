package ca.jettatelemetry.app.pocket

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

class PocketUploadWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        PocketStore.upload(applicationContext) { PocketState.upload = it }
        Result.success()
    } catch (failure: Exception) {
        PocketState.upload = "Queued for retry: ${failure.message}"
        Result.retry()
    }
    companion object {
        fun enqueue(context: Context) {
            val preferences = context.getSharedPreferences("pocket", Context.MODE_PRIVATE)
            if (preferences.getString("endpoint", "").isNullOrBlank()) return
            val network = if (preferences.getBoolean("unmetered", false)) NetworkType.UNMETERED else NetworkType.CONNECTED
            val work = OneTimeWorkRequestBuilder<PocketUploadWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(network).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build()
            // APPEND_OR_REPLACE avoids dropping a new recording queued as an older worker finishes.
            WorkManager.getInstance(context).enqueueUniqueWork("pocket-uploads", ExistingWorkPolicy.APPEND_OR_REPLACE, work)
        }
    }
}
