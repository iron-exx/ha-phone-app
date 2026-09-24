package de.haphone.app.test

import android.content.Context
import android.net.Uri
import android.telecom.DisconnectCause
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Wraps androidx.core.telecom's CallsManager to register this app as a
 * self-managed calling app with the Android Telecom framework (RESEARCH.md
 * Pattern 3). This is what qualifies the app for the Android 14+ full-screen-
 * intent auto-grant once the Play Console "calling app" declaration (Plan 05)
 * is also in place.
 *
 * NOTE: androidx.core.telecom 1.0.0's `CallsManager.addCall` is a suspend
 * function taking 4 positional callback lambdas (onAnswer: (Int) -> Unit,
 * onDisconnect: (DisconnectCause) -> Unit, onSetActive: () -> Unit,
 * onSetInactive: () -> Unit) plus a trailing CallControlScope block --
 * confirmed against the compiled androidx.core:core-telecom:1.0.0 classes
 * since the exact parameter names are not part of the public API contract
 * (RESEARCH.md Assumptions Log A3 flagged this as MEDIUM confidence).
 * Positional (unnamed) arguments are used deliberately here so this code
 * does not depend on guessed named-parameter labels.
 */
/** sip: address with the plain number, so Android Auto / Bluetooth show the number, not an app id. */
internal fun callAddress(number: String): Uri = Uri.fromParts("sip", number.ifBlank { "unknown" }, null)

class CallRegistration(private val context: Context) {
    private val callsManager = CallsManager(context)

    // A failing child (CallException from addCall, a SWIG exception in a callback) must neither
    // kill the process nor cancel the scope for every later call: SupervisorJob + handler.
    private val errors = CoroutineExceptionHandler { _, e -> Log.e(TAG, "uncaught in Telecom coroutine", e) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default + errors)

    // Code review WR-1 fix: Endpoint.libCreate()/libInit()/libStart() run on
    // the main thread (HAPhoneTestApplication.onCreate()) -- PJSIP aborts
    // with a native assertion ("Calling pjlib from unknown/external
    // thread") if any other, unregistered thread calls into it. Whether
    // androidx.core.telecom's addCall callbacks (onAnswer/onDisconnect) and
    // its trailing onRegistered block run on the calling coroutine's
    // dispatcher or on Telecom's own binder thread is not documented by the
    // library, so every call that reaches the SIP layer or the app's call
    // state is routed through this main-dispatcher scope explicitly.
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main + errors)

    private val app get() = context.applicationContext as HAPhoneTestApplication

    /** Runs [block] on main; a PJSIP/SWIG exception is logged instead of crashing (HANDOFF 7). */
    private fun onMain(what: String, block: () -> Unit) {
        mainScope.launch {
            runCatching(block).onFailure { Log.e(TAG, "$what failed", it) }
        }
    }

    /**
     * The car's (or a headset's) mute button goes through Telecom, which mutes the
     * microphone system-wide; mirror it into our call state so the phone UI agrees.
     */
    private fun watchTelecomMute(callScope: CallControlScope) {
        callScope.launch {
            runCatching {
                callScope.isMuted.collect { muted -> onMain("mute sync") { app.onTelecomMuteChanged(muted) } }
            }.onFailure { if (it is CancellationException) throw it else Log.w(TAG, "mute watch ended", it) }
        }
    }

    fun registerApp() {
        callsManager.registerAppWithTelecom(CallsManager.CAPABILITY_BASELINE)
    }

    /** Called on main once Telecom handed back the scope; a call ended meanwhile is disconnected at once. */
    private fun registered(token: Int, callScope: CallControlScope, direction: String, number: String): Boolean {
        if (!app.telecom.onRegistered(token, callScope)) {
            Log.i(TAG, "Telecom call $token registered after its call ended -> disconnected")
            return false
        }
        de.haphone.app.test.calls.AudioRouting.attach(callScope)
        watchTelecomMute(callScope)
        if (app.telecom.isAnswered(token)) {
            // Answered on our screen before Telecom was ready: tell Telecom now.
            callScope.launch {
                runCatching { callScope.answer(CallAttributesCompat.CALL_TYPE_AUDIO_CALL) }
                    .onFailure { if (it is CancellationException) throw it else Log.w(TAG, "late Telecom answer failed", it) }
            }
        } else {
            CallEventBus.emitCallState(number, direction, if (direction == "incoming") "ringing" else "connecting")
        }
        return true
    }

    /**
     * Reports an incoming call to Telecom. Main thread. Returns the Telecom token (see
     * [TelecomCalls]); the Telecom call is bound to [sipCallId] (null for a push-woken call
     * whose INVITE has not arrived yet). Telecom's answer/disconnect act on exactly that
     * SIP call, not on whatever call happens to be on screen.
     *
     * NOT `suspend` block: `CallsManager.addCall`'s trailing block parameter is a plain
     * `Function1<CallControlScope, Unit>` per the compiled API (confirmed via javap).
     */
    fun reportIncomingCall(
        sipCallId: Int?,
        number: String,
        displayName: String = CallNotificationBuilder.UNKNOWN_CALLER,
    ): Int {
        val token = app.telecom.beginIncoming(sipCallId)
        val attributes = CallAttributesCompat(
            displayName = displayName.ifBlank { CallNotificationBuilder.UNKNOWN_CALLER },
            address = callAddress(number),
            direction = CallAttributesCompat.DIRECTION_INCOMING,
            callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
        )
        scope.launch {
            try {
                callsManager.addCall(
                    attributes,
                    {
                        // Telecom invokes this ONLY on a genuine user answer from a system surface
                        // (car, Bluetooth, watch) -- never at registration time. Mirrors iOS's
                        // CXAnswerCallAction gating in CallProvider.swift.
                        onMain("Telecom answer") { app.onTelecomAnswer(token) }
                        CallEventBus.emitCallState(number, "incoming", "active")
                    },
                    { cause: DisconnectCause ->
                        onMain("Telecom disconnect") { app.onTelecomDisconnect(token) }
                        CallEventBus.emitCallState(number, "incoming", "disconnected", cause.toString())
                    },
                    // Remote surfaces (Android Auto's in-call view, Bluetooth) hold/resume through these.
                    { onMain("Telecom resume") { app.onTelecomHoldRequest(false) } },
                    { onMain("Telecom hold") { app.onTelecomHoldRequest(true) } },
                ) {
                    val callScope = this
                    onMain("Telecom registered") { registered(token, callScope, "incoming", number) }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // CallException (e.g. Telecom refuses during an emergency call): the SIP call keeps
                // ringing on our own screen and stays answerable, just without car/Bluetooth.
                Log.e(TAG, "Telecom addCall (incoming) failed", e)
                onMain("Telecom failure") { app.telecom.onFailed(token) }
            }
        }
        return token
    }

    /**
     * Outbound counterpart to [reportIncomingCall]. Main thread. [onRegistered] runs on main
     * once Telecom registered the call (Report-First: the SIP INVITE fires from there) and
     * gets the token so the SIP call id can be bound to it; it is skipped if the call was
     * already released. [onFailed] runs on main when Telecom refused the call.
     */
    fun reportOutgoingCall(
        number: String,
        displayName: String = number,
        onFailed: (Throwable) -> Unit = {},
        onRegistered: (token: Int) -> Unit,
    ): Int {
        val token = app.telecom.beginOutgoing()
        val attributes = CallAttributesCompat(
            displayName = displayName,
            address = callAddress(number),
            direction = CallAttributesCompat.DIRECTION_OUTGOING,
            callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
        )
        scope.launch {
            try {
                callsManager.addCall(
                    attributes,
                    { /* onAnswer: the SIP 200 OK of our own INVITE drives media, nothing to do. */
                        CallEventBus.emitCallState(number, "outgoing", "active")
                    },
                    { cause: DisconnectCause ->
                        onMain("Telecom disconnect") { app.onTelecomDisconnect(token) }
                        CallEventBus.emitCallState(number, "outgoing", "disconnected", cause.toString())
                    },
                    { onMain("Telecom resume") { app.onTelecomHoldRequest(false) } },
                    { onMain("Telecom hold") { app.onTelecomHoldRequest(true) } },
                ) {
                    val callScope = this
                    onMain("Telecom registered") {
                        if (registered(token, callScope, "outgoing", number)) onRegistered(token)
                        else onFailed(IllegalStateException("call ended before Telecom registered it"))
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Telecom addCall (outgoing) failed", e)
                onMain("Telecom failure") {
                    app.telecom.onFailed(token)
                    onFailed(e)
                }
            }
        }
        return token
    }

    private companion object {
        const val TAG = "CallRegistration"
    }
}
