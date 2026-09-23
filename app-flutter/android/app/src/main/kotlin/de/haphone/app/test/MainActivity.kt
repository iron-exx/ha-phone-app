package de.haphone.app.test

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter migration: replaces the old Compose MainActivity. Attaches to
 * the FlutterEngine created and cached in HAPhoneTestApplication.onCreate
 * (getCachedEngineId) so launch is fast whether started normally or as the
 * hand-off target from IncomingCallActivity's Answer action.
 * configureFlutterEngine() below (which registers the sip_calls/call_events
 * channel handlers) always runs before that cached engine's Dart
 * entrypoint executes -- see HAPhoneTestApplication's onCreate comment for
 * why that ordering matters.
 */
class MainActivity : FlutterActivity() {
    private var methodChannel: MethodChannel? = null

    override fun getCachedEngineId(): String = HAPhoneTestApplication.FLUTTER_ENGINE_ID

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The sip_calls/call_events handlers are registered with the engine in
        // HAPhoneTestApplication.onCreate (before Dart starts), not here.
        methodChannel = (application as HAPhoneTestApplication).sipMethodChannel
        deliverRouteIfAny(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverRouteIfAny(intent)
    }

    /** Cold-start-or-already-running-safe hand-off from IncomingCallActivity:
     * whether MainActivity is created fresh or already alive and receives
     * this via onNewIntent, Dart gets an explicit "navigateTo" call rather
     * than relying only on the live call_events stream (which a not-yet-
     * listening Dart side could miss). */
    private fun deliverRouteIfAny(intent: Intent) {
        val data = intent.data
        if (intent.action == Intent.ACTION_VIEW && data?.scheme == "haphone" && data.host == "provision") {
            // Consume it so a later configuration change does not pair a second time.
            intent.data = null
            methodChannel?.invokeMethod("navigateTo", "provision:$data")
            return
        }
        val route = intent.getStringExtra("route") ?: return
        methodChannel?.invokeMethod("navigateTo", route)
    }

    companion object {
        const val SIP_METHOD_CHANNEL = "de.haphone.app.test/sip_calls"
        const val SIP_EVENT_CHANNEL = "de.haphone.app.test/call_events"
    }
}
