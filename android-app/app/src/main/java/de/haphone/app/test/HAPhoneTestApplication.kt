package de.haphone.app.test

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.ConnectivityManager
import androidx.core.app.NotificationManagerCompat
import de.haphone.app.test.sip.NetworkChangeHandler
import de.haphone.app.test.sip.PjsuaEndpointHolder

/**
 * Ensures the incoming-call notification channel exists before any FCM
 * message can arrive -- registering it lazily inside CallNotificationBuilder
 * would race the very first push. Also owns the process-lifetime PJSUA2
 * Endpoint (PjsuaEndpointHolder) and the platform network-change observer
 * that drives its D-09 mid-call network-switch recovery path.
 */
class HAPhoneTestApplication : Application() {
    val pjsuaEndpointHolder = PjsuaEndpointHolder()
    private val networkChangeHandler = NetworkChangeHandler(pjsuaEndpointHolder)
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CallNotificationBuilder.CHANNEL_ID,
            "HA-Phone Test Calls",
            NotificationManager.IMPORTANCE_HIGH,
        )
        NotificationManagerCompat.from(this).createNotificationChannel(channel)
        pjsuaEndpointHolder.start()

        // D-09: mid-call network-switch resilience (RESEARCH.md Pattern 3) --
        // observe platform network changes for the app process lifetime and
        // route them through the testable NetworkChangeHandler seam.
        val connectivityManager = getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: android.net.Network) {
                networkChangeHandler.onNetworkAvailable()
            }
        }
        connectivityManager?.registerDefaultNetworkCallback(callback)
        networkCallback = callback
    }
}
