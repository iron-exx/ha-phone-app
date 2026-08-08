package de.haphone.app.test

import android.content.Context
import android.net.Uri
import android.telecom.DisconnectCause
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import de.haphone.app.test.sip.SipCallController
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
class CallRegistration(private val context: Context, private val sipCallController: SipCallController) {
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
            // Blocker fix (checker iteration 4): addCall's onAnswer/
            // onDisconnect/onSetActive/onSetInactive lambdas are NOT
            // CallControlScope receivers themselves -- only the trailing
            // `block` lambda below is. The live scope is captured into
            // this local var from inside that trailing block so onAnswer
            // (which fires later, only on the platform's genuine
            // user-answer signal) can reach disconnect() on SIP-answer
            // failure (CR-01 precedent).
            var liveScope: CallControlScope? = null
            callsManager.addCall(
                attributes,
                {
                    // Blocker fix: Telecom invokes this lambda ONLY when
                    // the user actually answers via the system CallStyle
                    // action -- the genuine user-answer signal. The real
                    // SIP answer() call is gated HERE, not in the
                    // trailing onRegistered block below (which fires at
                    // registration-complete time -- essentially at
                    // push-arrival time, long before any user
                    // interaction or SIP INVITE could plausibly exist).
                    // A prior revision called sipCallController.answer()
                    // unconditionally in the trailing block instead,
                    // which meant answer() always ran before any call
                    // could actually be answered. Mirrors iOS's
                    // already-correct CXAnswerCallAction gating in
                    // CallProvider.swift.
                    liveScope?.let { sipCallController.answer(it) }
                },
                { _: DisconnectCause -> sipCallController.hangup() },
                { /* onSetActive */ },
                { /* onSetInactive */ },
            ) {
                // Stash the live CallControlScope BEFORE onRegistered()
                // runs, so ActiveCallActivity (Plan 06) always has a real
                // scope to read for Audio Routing (CALL-01), for both
                // incoming and outgoing calls -- and so the onAnswer
                // callback above (captured via liveScope) has a scope to
                // call disconnect() on if SIP negotiation fails once the
                // user actually answers.
                liveScope = this
                (context.applicationContext as HAPhoneTestApplication).currentCallControlScope = this
                onRegistered()
            }
        }
    }

    /**
     * Outbound counterpart to [reportIncomingCall] (Blocker fix). Mirrors
     * its exact shape with DIRECTION_OUTGOING; `addCall` is
     * direction-agnostic on the Telecom side, so only the `direction`
     * value and what the trailing lambda does differ -- there is no SIP
     * answer step for an outgoing call, only the scope stash. The caller
     * (Plan 06's OutgoingCallActivity) invokes
     * `sipCallController.makeCall(...)` from inside its own
     * `onRegistered` block, so the SIP INVITE only fires once Telecom has
     * actually reported the call (Report-First pattern, same discipline
     * as the incoming path).
     */
    fun reportOutgoingCall(callId: String, onRegistered: CallControlScope.() -> Unit) {
        val attributes = CallAttributesCompat(
            displayName = "HA-Phone Testanruf",
            address = Uri.parse("haphone:$callId"),
            direction = CallAttributesCompat.DIRECTION_OUTGOING,
            callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
        )
        scope.launch {
            callsManager.addCall(
                attributes,
                { /* onAnswer: Telecom may invoke this for a self-managed
                     outgoing call once the far end picks up -- no SIP
                     action needed here; the SIP 200 OK for an outgoing
                     call already drives media setup via makeCall's own
                     INVITE transaction, not a Telecom-side callback. */
                },
                { _: DisconnectCause -> sipCallController.hangup() },
                { /* onSetActive */ },
                { /* onSetInactive */ },
            ) {
                (context.applicationContext as HAPhoneTestApplication).currentCallControlScope = this
                onRegistered()
            }
        }
    }
}
