package de.haphone.app.test.sip

import android.telecom.DisconnectCause
import androidx.core.telecom.CallControlScope
import kotlinx.coroutines.launch

/**
 * Public SIP call-control API for Android (CALL-01..05). Wraps
 * [SipCallOperations] (the real PJSUA2-backed implementation lives in
 * PjsuaEndpointHolder's companion usage from HAPhoneTestApplication) and
 * always sanitizes digit input via [DialString] before constructing a
 * sip: URI (Security V5, T-2-08).
 *
 * sipDomain is the Phase 2 TLS/SRTP test extension's host:port (Plan 01's
 * "transport-tls" listens on 5061) -- configured once, not per-call.
 */
class SipCallController(
    private val sipOps: SipCallOperations,
    private val sipDomain: String,
) {
    fun makeCall(rawDigits: String) {
        val uri = DialString.toSipUri(DialString.sanitize(rawDigits), sipDomain)
        sipOps.register()
        sipOps.makeCall(uri)
    }

    /**
     * Report-First pattern (02-PATTERNS.md): called from
     * CallRegistration's real onAnswer callback, gated on the platform's
     * genuine user-answer signal (checker blocker fix, iteration 4) --
     * NEVER from the trailing onRegistered block, which fires at
     * registration-complete/push-arrival time, long before the user has
     * done anything. Registers transiently (CALL-05), then attempts SIP
     * answer against whatever Call Account.onIncomingCall has already
     * populated (PjsuaEndpointHolder's Blocker-1 fix); on failure --
     * including "no active call exists yet" -- disconnects via the
     * CallControlScope receiver rather than ringing forever (CR-01
     * precedent).
     */
    fun answer(callControlScope: CallControlScope) {
        sipOps.register()
        val succeeded = sipOps.answer()
        if (!succeeded) {
            // Rule 1 fix: androidx.core.telecom 1.0.0's CallControlScope.disconnect()
            // is `suspend fun disconnect(disconnectCause: DisconnectCause): CallControlResult`
            // (confirmed via javap against the compiled AAR) -- not a no-arg call.
            // ERROR mirrors "something went wrong establishing the call", distinct
            // from TestFcmService's REJECTED (forged/expired push) cause.
            callControlScope.launch { callControlScope.disconnect(DisconnectCause(DisconnectCause.ERROR)) }
        }
    }

    fun hold(onHold: Boolean) = sipOps.hold(onHold)
    fun mute(muted: Boolean) = sipOps.mute(muted)

    fun transfer(rawDigits: String) {
        val uri = DialString.toSipUri(DialString.sanitize(rawDigits), sipDomain)
        sipOps.transfer(uri)
    }

    fun sendDtmf(rawDigit: String) {
        val digit = DialString.sanitize(rawDigit)
        if (digit.isNotEmpty()) sipOps.sendDtmf(digit)
    }

    fun hangup() {
        sipOps.hangup()
        sipOps.unregister()
    }
}
