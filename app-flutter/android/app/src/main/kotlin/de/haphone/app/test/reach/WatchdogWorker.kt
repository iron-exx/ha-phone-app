package de.haphone.app.test.reach

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import de.haphone.app.test.HAPhoneTestApplication
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Every 15 minutes (WorkManager minimum, no constraints -- it must also run
 * without network to notice that): is the service running, is the extension
 * registered? If not, repair it; otherwise re-arm the refresh alarm. Runs in
 * Doze maintenance windows, so it is the safety net, not the primary refresh.
 */
class WatchdogWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val app = applicationContext as? HAPhoneTestApplication ?: return Result.success()
        // PJSIP is only driven from main; wait so WorkManager's wake lock covers the dispatch.
        val done = CountDownLatch(1)
        Handler(Looper.getMainLooper()).post {
            try {
                ReachabilityMonitor.runWatchdog(app)
            } catch (e: Exception) {
                Log.e(ReachabilityMonitor.TAG, "watchdog failed", e)
            } finally {
                done.countDown()
            }
        }
        if (!done.await(MAIN_WAIT_SEC, TimeUnit.SECONDS)) Log.w(ReachabilityMonitor.TAG, "watchdog: main thread busy")
        return Result.success()
    }

    companion object {
        private const val UNIQUE_NAME = "haphone-reach-watchdog"
        private const val MAIN_WAIT_SEC = 10L

        /** Idempotent (KEEP): an already scheduled watchdog keeps its period. */
        fun ensureScheduled(context: Context) {
            runCatching {
                val request = PeriodicWorkRequestBuilder<WatchdogWorker>(ReachPolicy.WATCHDOG_INTERVAL_MIN, TimeUnit.MINUTES).build()
                WorkManager.getInstance(context)
                    .enqueueUniquePeriodicWork(UNIQUE_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
            }.onFailure { Log.w(ReachabilityMonitor.TAG, "watchdog not scheduled", it) }
        }

        fun cancel(context: Context) {
            runCatching { WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_NAME) }
        }
    }
}
