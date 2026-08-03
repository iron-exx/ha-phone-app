package de.haphone.app.test

import android.content.Context
import android.net.Uri
import android.telecom.DisconnectCause
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
class CallRegistration(private val context: Context) {
    private val callsManager = CallsManager(context)
    private val scope = CoroutineScope(Dispatchers.Default)

    fun registerApp() {
        callsManager.registerAppWithTelecom(CallsManager.CAPABILITY_BASELINE)
    }

    /**
     * [onRegistered] runs inside the [CallControlScope] Telecom hands back once
     * the call is registered -- receiver type deliberately exposes `disconnect()`
     * (not just a plain `() -> Unit`) so a caller that determines the envelope
     * is invalid/expired can end the call itself, mirroring iOS's
     * `PushHandler.handleIncomingPush` which calls `callEnder.endCall(uuid:)`
     * after reporting. Without this, the equivalent Android call would ring
     * forever on a forged/expired push (see code review CR-01).
     *
     * NOT `suspend`: `CallsManager.addCall`'s trailing block parameter is a
     * plain `Function1<CallControlScope, Unit>` per the compiled API (confirmed
     * via javap), not a suspend function type. `CallControlScope` itself extends
     * `CoroutineScope`, so callers that need to call a suspend member like
     * `disconnect()` must wrap that call in `launch { ... }`.
     */
    fun reportIncomingCall(callId: String, onRegistered: CallControlScope.() -> Unit) {
        val attributes = CallAttributesCompat(
            displayName = "HA-Phone Testanruf",
            address = Uri.parse("haphone:$callId"),
            direction = CallAttributesCompat.DIRECTION_INCOMING,
            callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
        )
        scope.launch {
            callsManager.addCall(
                attributes,
                { /* onAnswer: log reportedAt / accepted */ },
                { _: DisconnectCause -> /* onDisconnect */ },
                { /* onSetActive */ },
                { /* onSetInactive */ },
            ) {
                // Runs once Telecom has registered the call, with `this` bound to
                // CallControlScope -- post the CallStyle notification + full-screen
                // intent from here, and disconnect() is available if needed.
                onRegistered()
            }
        }
    }
}
