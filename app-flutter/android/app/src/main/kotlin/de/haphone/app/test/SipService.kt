package de.haphone.app.test

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Foreground service that keeps the process -- and with it the PJSIP TLS
 * registration -- alive while the app is in the background or the screen is off,
 * so incoming calls arrive like on a normal phone. Started from the app once it
 * is provisioned and again after every reboot.
 */
class SipService : Service() {

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        instance = java.lang.ref.WeakReference(this)
        inCallMode = false
        android.util.Log.i(de.haphone.app.test.reach.ReachabilityMonitor.TAG, "service created")
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Verbindung", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Hält die Verbindung zur Telefonanlage, damit Anrufe ankommen."
                setShowBadge(false)
            },
        )
        enterForeground(inCall = false)
    }

    private fun buildNotification(inCall: Boolean) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_stat_haphone)
        .setContentTitle(if (inCall) "HA-Phone: Gespräch läuft" else "HA-Phone ist bereit")
        .setContentText(if (inCall) "Tippen, um zum Gespräch zu wechseln" else "Eingehende Anrufe werden empfangen")
        .setContentIntent(
            PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java).apply { if (inCall) putExtra("route", "active_call") },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        )
        .setOngoing(true)
        .setCategory(if (inCall) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_SERVICE)
        .build()

    /**
     * Idle: specialUse only -- Android 15 forbids starting phoneCall-type services from
     * BOOT_COMPLETED, and this service must come back after a reboot.
     * In a call: phoneCall|microphone on top, so the microphone keeps working when the call
     * was answered from the background (car, headset) -- without a microphone-type foreground
     * service Android 11+ records silence for an app that is not visible. Falls back step by
     * step if the system refuses a type (SecurityException, e.g. RECORD_AUDIO not granted or
     * a while-in-use restriction on Android 14+).
     */
    private fun enterForeground(inCall: Boolean) {
        val notification = buildNotification(inCall)
        for (type in ForegroundTypes.candidates(Build.VERSION.SDK_INT, inCall)) {
            val ok = runCatching { ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type) }
                .onFailure { android.util.Log.w("SipService", "startForeground type=$type refused", it) }
                .isSuccess
            if (ok) {
                android.util.Log.i("SipService", "foreground inCall=$inCall type=$type")
                return
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        runCatching { (application as HAPhoneTestApplication).sipCallController.register() }
            .onFailure { android.util.Log.w("SipService", "SIP register failed", it) }
        // Also covers a START_STICKY restart after the process was killed.
        de.haphone.app.test.reach.WatchdogWorker.ensureScheduled(this)
        return START_STICKY
    }

    /** User swiped the app away: the service normally survives, but some OEMs kill the process next. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        de.haphone.app.test.reach.ReachabilityMonitor.onTaskRemoved(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        android.util.Log.w(de.haphone.app.test.reach.ReachabilityMonitor.TAG, "service destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        /** True between onCreate and onDestroy (same process only), for the watchdog and the snapshot. */
        @Volatile
        var isRunning = false
            private set

        private const val CHANNEL_ID = "haphone_service"
        private const val NOTIFICATION_ID = 1002

        private var instance: java.lang.ref.WeakReference<SipService>? = null
        private var inCallMode = false

        /**
         * Switch the running service between idle and in-call foreground types. Main thread.
         * No-op when the service is not running (not provisioned): it cannot be started with
         * the microphone type from the background anyway.
         */
        fun setInCall(inCall: Boolean) {
            // Call screen over the keyguard (MainActivity) follows the same lifecycle; also
            // when the service is not running.
            de.haphone.app.test.calls.InCallWindow.setActive(inCall)
            if (inCallMode == inCall) return
            val service = instance?.get() ?: return
            inCallMode = inCall
            service.enterForeground(inCall)
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            android.util.Log.i(de.haphone.app.test.reach.ReachabilityMonitor.TAG, "boot/update: ${intent.action}")
            (context.applicationContext as HAPhoneTestApplication).startSipService()
        }
    }
}
