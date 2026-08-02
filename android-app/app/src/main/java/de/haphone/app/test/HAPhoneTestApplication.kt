package de.haphone.app.test

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.core.app.NotificationManagerCompat

/**
 * Ensures the incoming-call notification channel exists before any FCM
 * message can arrive -- registering it lazily inside CallNotificationBuilder
 * would race the very first push.
 */
class HAPhoneTestApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CallNotificationBuilder.CHANNEL_ID,
            "HA-Phone Test Calls",
            NotificationManager.IMPORTANCE_HIGH,
        )
        NotificationManagerCompat.from(this).createNotificationChannel(channel)
    }
}
