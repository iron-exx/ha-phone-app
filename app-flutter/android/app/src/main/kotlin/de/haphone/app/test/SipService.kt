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
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "HA-Phone Verbindung", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Hält die Verbindung zur Telefonanlage, damit Anrufe ankommen."
                setShowBadge(false)
            },
        )
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_haphone)
            .setContentTitle("HA-Phone ist bereit")
            .setContentText("Eingehende Anrufe werden empfangen")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        // specialUse, not phoneCall: Android 15 forbids starting phoneCall-type services
        // from BOOT_COMPLETED, and this service must come back after a reboot.
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        runCatching { (application as HAPhoneTestApplication).sipCallController.register() }
            .onFailure { android.util.Log.w("SipService", "SIP register failed", it) }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "haphone_service"
        private const val NOTIFICATION_ID = 1002
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            (context.applicationContext as HAPhoneTestApplication).startSipService()
        }
    }
}
