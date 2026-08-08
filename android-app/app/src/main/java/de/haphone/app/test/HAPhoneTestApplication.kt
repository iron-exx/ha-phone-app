package de.haphone.app.test

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.ConnectivityManager
import androidx.core.app.NotificationManagerCompat
import androidx.core.telecom.CallControlScope
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
     * Real HA-Phone test-extension host/port/username/password (Plan 01's
     * checkpoint output) compiled into the app config via BuildConfig fields
     * sourced from the already-gitignored android-app/local.properties (see
     * app/build.gradle.kts) -- deliberately NOT literal Kotlin string
     * constants here. This repo has a public GitHub remote; a real LAN PBX
     * password committed to git history is effectively permanent exposure
     * even after later rotation (kotlin/security.md: "Never hardcode API
     * keys, tokens, or credentials in source code... use local.properties
     * for local development secrets"). BuildConfig.SIP_TEST_* are still
     * "compiled into the app config" at build time, satisfying this plan's
     * functional requirement without a plaintext secret in tracked source.
     *
     * NOTE (pending-deploy caveat, see 02-04-SUMMARY.md): Plan 01 Task 3's
     * human-action checkpoint (restarting the real HA-Phone box to activate
     * the [transport-tls] Asterisk transport) has not been confirmed live
     * yet -- these are confirmed-valid extension credentials, but a real
     * end-to-end call has not been verified against the live box (deferred
     * to Plan 08's manual test procedure).
     */
    val sipCallController: SipCallController by lazy {
        val sipDomain = "${BuildConfig.SIP_TEST_HOST}:${BuildConfig.SIP_TEST_PORT}"
        SipCallController(
            sipOps = pjsuaEndpointHolder.asSipCallOperations(
                username = BuildConfig.SIP_TEST_USERNAME,
                password = BuildConfig.SIP_TEST_PASSWORD,
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
