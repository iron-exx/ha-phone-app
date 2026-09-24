package de.haphone.app.test.sip

import de.haphone.app.test.CallEventBus

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
    /**
     * Proactive register/unregister, independent of placing a call --
     * added for the Flutter migration's Settings screen (a "verify
     * credentials" affordance) and to give the EventChannel a
     * registration-state signal Dart can react to.
     */
    // The real registered/failed state is reported asynchronously by HAPhoneAccount.onRegState.
    fun register() {
        sipOps.register()
    }

    /** Refresh the registration right now (ReachabilityMonitor: alarm, transport drop, watchdog). */
    fun renewRegistration() {
        sipOps.renewRegistration()
    }

    fun unregister() {
        sipOps.unregister()
        CallEventBus.emitRegistrationState("unregistered")
    }

    /** Returns the pjsua call id. */
    fun makeCall(rawDigits: String): Int {
        val uri = DialString.toSipUri(DialString.sanitize(rawDigits), sipDomain)
        sipOps.register()
        return sipOps.makeCall(uri)
    }

    fun answerWaiting(): Boolean = sipOps.answerWaiting()
    fun rejectWaiting() = sipOps.rejectWaiting()
    fun swap(): Boolean = sipOps.swap()
    fun merge(): Boolean = sipOps.merge()
    fun transferAttended(): Boolean = sipOps.transferAttended()

    /**
     * Report-First pattern (02-PATTERNS.md): runs only on a genuine user answer (ringing
     * screen, notification action, or Telecom's onAnswer from car/headset) -- never at
     * Telecom registration time. Registers transiently (CALL-05), then answers exactly
     * [callId]. Returns false when that call is gone or SIP negotiation failed; the caller
     * ends the Telecom call then (CR-01 precedent). Throws what PJSIP throws.
     */
    fun answer(callId: Int): Boolean {
        sipOps.register()
        return sipOps.answer(callId)
    }

    /** Answer whatever call is on screen (push-woken call without a known SIP id). */
    fun answerCurrent(): Boolean {
        sipOps.register()
        return sipOps.answer()
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

    fun queueDtmfOnConnect(rawDigits: String) {
        val digits = DialString.sanitize(rawDigits)
        if (digits.isNotEmpty()) sipOps.queueDtmfOnConnect(digits)
    }

    // Registration stays up after hangup so the extension remains reachable.
    fun hangup() {
        sipOps.hangup()
    }

    fun hangup(callId: Int) {
        sipOps.hangup(callId)
    }
}
