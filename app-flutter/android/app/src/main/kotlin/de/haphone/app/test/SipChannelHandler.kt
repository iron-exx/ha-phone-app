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
                    val secondCall = app.currentCall != null
                    if (!app.calls.beginOutgoing(number)) {
                        result.error("SIP_BUSY", "Schon zwei Gespräche aktiv", null)
                        return
                    }
                    if (secondCall) {
                        // Consultation call inside the running Telecom call: no new Telecom call.
                        try {
                            app.calls.bindOutgoing(app.sipCallController.makeCall(number))
                        } catch (e: Exception) {
                            android.util.Log.e("SipChannelHandler", "second makeCall failed", e)
                            app.calls.failOutgoing()
                            CallEventBus.emitCallState(number, "outgoing", "lineEnded", e.message)
                        }
                        result.success(null)
                        return
                    }
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
                            app.calls.bindOutgoing(app.sipCallController.makeCall(number))
                        } catch (e: Exception) {
                            android.util.Log.e("SipChannelHandler", "makeCall failed", e)
                            app.calls.failOutgoing()
                            CallEventBus.emitCallState(number, "outgoing", "disconnected", e.message)
                            app.endTelecomSession(DisconnectCause.ERROR)
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
                    // With a second call the Telecom call stays: that call is still up.
                    if (app.calls.session.other == null) app.releaseTelecomCall(DisconnectCause.LOCAL)
                    result.success(null)
                }

                "answerWaiting" -> {
                    CallNotificationBuilder.cancelWaiting(app)
                    val ok = app.sipCallController.answerWaiting() && app.calls.acceptWaiting()
                    result.success(ok)
                }

                "rejectWaiting" -> {
                    CallNotificationBuilder.cancelWaiting(app)
                    app.sipCallController.rejectWaiting()
                    result.success(null)
                }

                "swapCalls" -> result.success(app.sipCallController.swap() && app.calls.swap())

                "mergeCalls" -> result.success(app.sipCallController.merge() && app.calls.startConference())

                "transferAttended" -> result.success(app.sipCallController.transferAttended())

                "hold" -> {
                    val onHold = call.arguments as Boolean
                    app.sipCallController.hold(onHold)
                    app.calls.setHold(onHold)
                    result.success(null)
                }

                "mute" -> {
                    val muted = call.arguments as Boolean
                    app.sipCallController.mute(muted)
                    app.calls.setMuted(muted)
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

                "saveDeviceAuth" -> {
                    val args = call.arguments as Map<*, *>
                    app.saveDeviceAuth(
                        apiHost = args["apiHost"] as? String ?: "",
                        deviceId = args["deviceId"] as? String ?: "",
                        deviceToken = args["deviceToken"] as? String ?: "",
                    )
                    result.success(null)
                }

                "getDeviceAuth" -> result.success(app.getDeviceAuth())

                "setDoorCodes" -> {
                    val codes = (call.arguments as? Map<*, *>).orEmpty()
                        .mapNotNull { (k, v) -> (k as? String)?.let { key -> (v as? String)?.let { key to it } } }
                        .toMap()
                    app.doorCodes.replaceAll(codes)
                    result.success(null)
                }

                "setDoorOpenRemote" -> {
                    val numbers = (call.arguments as? List<*>).orEmpty().filterIsInstance<String>()
                    app.doorCodes.replaceOpenRemote(numbers)
                    result.success(null)
                }

                "setDoorActions" -> {
                    val actions = (call.arguments as? Map<*, *>).orEmpty().mapNotNull { (k, v) ->
                        val number = k as? String ?: return@mapNotNull null
                        number to (v as? List<*>).orEmpty().filterIsInstance<String>()
                    }.toMap()
                    app.doorActions.replaceAll(actions)
                    result.success(null)
                }

                "runDoorAction" -> {
                    val args = call.arguments as Map<*, *>
                    app.runDoorAction(args["number"] as? String ?: "", (args["index"] as? Int) ?: -1) { error ->
                        if (error == null) result.success(null) else result.error("DOOR_ACTION", error, null)
                    }
                }

                "openDoor" -> {
                    val code = app.currentCall?.doorCode.orEmpty()
                    if (code.isNotEmpty()) app.sipCallController.sendDtmf(code)
                    result.success(code.isNotEmpty())
                }

                "getCurrentCall" -> result.success(app.calls.snapshot())

                "getAudioRoutes" -> result.success(de.haphone.app.test.calls.AudioRouting.snapshot())

                "setAudioRoute" -> result.success(
                    de.haphone.app.test.calls.AudioRouting.select(call.arguments as? String ?: ""),
                )

                "getCallHistory" -> result.success(app.callHistory.all().map { it.toChannelMap() })

                "deleteCallHistoryEntry" -> {
                    val id = call.arguments as? String ?: ""
                    app.callHistory.update { de.haphone.app.test.calls.CallHistory.remove(it, id) }
                    result.success(null)
                }

                "clearCallHistory" -> {
                    app.callHistory.update { emptyList() }
                    result.success(null)
                }

                "getRegistrationState" -> result.success(CallEventBus.lastRegistrationState)

                // Erreichbarkeit: permissions, battery/alarm state, registration timing, OEM.
                "getReachability" -> result.success(
                    de.haphone.app.test.reach.ReachabilityMonitor.snapshot(app) +
                        ("registrationState" to CallEventBus.lastRegistrationState),
                )

                // Argument: exactAlarm | batteryOptimization | fullScreenIntent | notifications | appDetails
                "openReachabilitySettings" -> {
                    val target = de.haphone.app.test.reach.ReachSettings.Target.fromKey(call.arguments as? String)
                    if (target == null) {
                        result.error("BAD_ARGS", "unknown settings page: ${call.arguments}", null)
                    } else {
                        result.success(de.haphone.app.test.reach.ReachSettings.open(app, target))
                    }
                }

                // "Klingeln auf diesem Handy" (local, see ring/RingPolicy.kt).
                "getRingPolicy" -> result.success(de.haphone.app.test.ring.RingPolicyStore.load().toMap())

                "setRingPolicy" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("BAD_ARGS", "map expected", null)
                    } else {
                        val store = de.haphone.app.test.ring.RingPolicyStore
                        val next = de.haphone.app.test.ring.RingPolicy.fromMap(args, store.load())
                        result.success(store.save(next).toMap())
                    }
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
