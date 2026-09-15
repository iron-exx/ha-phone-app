package de.haphone.app.test

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import androidx.core.app.NotificationManagerCompat
import androidx.core.telecom.CallControlScope
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import de.haphone.app.test.sip.NetworkChangeHandler
import de.haphone.app.test.sip.PjsuaEndpointHolder
import de.haphone.app.test.sip.SipCallController

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

    // Blocker fix: the only source ActiveCallActivity (Plan 06) reads for
    // CallControlScope.availableEndpoints/requestEndpointChange (Audio
    // Routing, CALL-01). Stashed by CallRegistration.reportIncomingCall AND
    // reportOutgoingCall's trailing lambda (both directions), overwritten
    // each time a new call is reported so it always reflects the current call.
    var currentCallControlScope: CallControlScope? = null

    /**
     * SIP-Call-Controller: verwendet gespeicherte Credentials aus EncryptedSharedPreferences,
     * fällt auf BuildConfig zurück (für Test/Dev ohne Provisioning).
     */
    val sipCallController: SipCallController by lazy {
        val (host, port, username, password) = getSipCredentials(this)
        val sipDomain = "$host:$port"
        SipCallController(
            sipOps = pjsuaEndpointHolder.asSipCallOperations(
                username = username,
                password = password,
                domain = sipDomain,
            ),
            sipDomain = sipDomain,
        )
    }

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CallNotificationBuilder.CHANNEL_ID,
            "HA-Phone Test Calls",
            NotificationManager.IMPORTANCE_HIGH,
        )
        NotificationManagerCompat.from(this).createNotificationChannel(channel)

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

    private fun getSipCredentials(context: Context): List<String> {
        val prefs = getEncryptedPrefs(context)
        val host = prefs.getString("sip_host", "") ?: BuildConfig.SIP_TEST_HOST
        val port = prefs.getString("sip_port", "") ?: BuildConfig.SIP_TEST_PORT
        val username = prefs.getString("sip_username", "") ?: BuildConfig.SIP_TEST_USERNAME
        val password = prefs.getString("sip_password", "") ?: BuildConfig.SIP_TEST_PASSWORD
        return listOf(host, port, username, password)
    }

    private fun getEncryptedPrefs(context: Context): SharedPreferences {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        return EncryptedSharedPreferences.create(
            "haphone_prefs",
            masterKeyAlias,
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }
}
