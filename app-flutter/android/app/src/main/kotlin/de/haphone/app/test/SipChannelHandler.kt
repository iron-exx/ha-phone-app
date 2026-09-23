package de.haphone.app.test

import android.provider.Settings
import android.telecom.DisconnectCause
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * MethodChannel("de.haphone.app.test/sip_calls") + EventChannel
 * ("de.haphone.app.test/call_events") handler -- the platform-channel
 * bridge between the Flutter UI and the existing (unmodified) SIP/Telecom
 * native layer owned by HAPhoneTestApplication.
 *
 * All PJSIP-touching calls here run on whatever thread MethodChannel
 * invokes onMethodCall on -- the Android platform/UI thread by default,
 * matching the exact thread PjsuaEndpointHolder.start() ran on. Do NOT
 * wrap any of this in a background dispatcher "to be safe": PJSIP
 * natively asserts/aborts (uncatchable) if called from a thread other
 * than the one its Endpoint was created on (see CallRegistration's WR-1
 * comment for the same constraint on the Telecom side).
 */
class SipChannelHandler(
    private val app: HAPhoneTestApplication,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val mainScope = CoroutineScope(Dispatchers.Main)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasValidCredentials" -> result.success(app.hasValidCredentials())

                "getCredentials" -> result.success(app.getStoredCredentials())

                "saveCredentials" -> {
                    val args = call.arguments as Map<*, *>
                    app.saveCredentials(
                        host = args["host"] as? String ?: "",
                        port = args["port"] as? String ?: "",
                        username = args["username"] as? String ?: "",
                        password = args["password"] as? String ?: "",
                    )
                    app.refreshSipCredentials()
                    result.success(null)
                }

                "clearCredentials" -> {
                    app.clearCredentials()
                    result.success(null)
                }

                "register" -> {
                    app.sipCallController.register()
                    app.startSipService()
                    requestBatteryOptimizationExemption()
                    result.success(null)
                }

                "unregister" -> {
                    app.sipCallController.unregister()
                    result.success(null)
                }

                "makeCall" -> {
                    val number = call.arguments as? String ?: ""
                    // Re-homed from the old OutgoingCallActivity's onClick:
                    // report the call to Telecom first (Report-First
                    // pattern), and only fire the real SIP INVITE from
                    // inside reportOutgoingCall's onRegistered block, once
                    // Telecom has actually registered it -- never
                    // synchronously here, which would race
                    // currentCallControlScope's stash (see CallRegistration).
                    app.callRegistration.reportOutgoingCall(callId = number) {
                        // Runs later inside a coroutine, outside this method's try/catch -- an uncaught PJSIP error here kills the process.
                        try {
                            app.sipCallController.makeCall(number)
                        } catch (e: Exception) {
                            android.util.Log.e("SipChannelHandler", "makeCall failed", e)
                            CallEventBus.emitCallState(number, "outgoing", "disconnected", e.message)
                            app.releaseTelecomCall(DisconnectCause.ERROR)
                        }
                    }
                    result.success(null)
                }

                "hangup" -> {
                    // A call that already failed/ended throws ESESSIONTERMINATED; Telecom must still be released below.
                    runCatching { app.sipCallController.hangup() }
                        .onFailure { android.util.Log.w("SipChannelHandler", "SIP hangup failed", it) }
                    // Fix: the old ActiveCallActivity called only
                    // sipCallController.hangup(), never
                    // CallControlScope.disconnect() -- unlike the (correct)
                    // Decline path in IncomingCallActivity, which does
                    // both. Doing both here keeps Telecom's own call state
                    // in sync instead of leaving a "phantom" registered
                    // call behind.
                    app.releaseTelecomCall(DisconnectCause.LOCAL)
                    result.success(null)
                }

                "hold" -> {
                    app.sipCallController.hold(call.arguments as Boolean)
                    result.success(null)
                }

                "mute" -> {
                    app.sipCallController.mute(call.arguments as Boolean)
                    result.success(null)
                }

                "transfer" -> {
                    app.sipCallController.transfer(call.arguments as? String ?: "")
                    result.success(null)
                }

                "sendDtmf" -> {
                    app.sipCallController.sendDtmf(call.arguments as? String ?: "")
                    result.success(null)
                }

                "getDeviceId" -> {
                    val deviceId = Settings.Secure.getString(
                        app.contentResolver,
                        Settings.Secure.ANDROID_ID,
                    )
                    result.success(deviceId)
                }

                "getFcmToken" -> {
                    // Genuinely async -- result.success must fire from the
                    // completion listener, not synchronously here, or the
                    // MethodChannel result would be missing entirely.
                    FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                        result.success(if (task.isSuccessful) task.result else null)
                    }
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("SIP_ERROR", e.message, null)
        }
    }

    /** Doze would otherwise cut the network and drop the SIP registration while the screen is off. */
    private fun requestBatteryOptimizationExemption() {
        val power = app.getSystemService(android.os.PowerManager::class.java) ?: return
        if (power.isIgnoringBatteryOptimizations(app.packageName)) return
        runCatching {
            app.startActivity(
                android.content.Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(android.net.Uri.parse("package:${app.packageName}"))
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }.onFailure { android.util.Log.w("SipChannelHandler", "battery exemption request failed", it) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        CallEventBus.sink = events
    }

    override fun onCancel(arguments: Any?) {
        CallEventBus.sink = null
    }
}
