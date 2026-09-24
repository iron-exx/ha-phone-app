package de.haphone.app.test.sip

/**
 * Thin seam wrapping the PJSUA2 Call/Account C++ objects, mirroring the
 * iOS SipCallOperations protocol (02-PATTERNS.md "Protocol/Interface
 * Abstraction for Testability"). PjsuaEndpointHolder provides the real
 * implementation; unit tests inject a fake.
 */
interface SipCallOperations {
    fun register()
    fun unregister()
    /** Re-REGISTER now (Doze alarm, dropped connection); creates the account if it is gone. */
    fun renewRegistration() = register()
    /** Returns the new pjsua call id; an existing call is put on hold behind it. */
    fun makeCall(uri: String): Int
    fun answer(): Boolean // false = SIP negotiation failed
    /** Answer exactly this SIP call (the one Telecom / the ringing screen stands for); false if it is gone. */
    fun answer(callId: Int): Boolean = answer()
    fun hold(onHold: Boolean)
    fun mute(muted: Boolean)
    fun transfer(uri: String)
    fun sendDtmf(digit: String)
    /** Send [digits] as soon as the current call is answered. */
    fun queueDtmfOnConnect(digits: String) {}
    /** Call waiting: answer the second call, the current one goes on hold. */
    fun answerWaiting(): Boolean = false
    fun rejectWaiting() {}
    /** Makeln between the two calls. */
    fun swap(): Boolean = false
    /** 3-way conference of both calls. */
    fun merge(): Boolean = false
    /** Connect the held party with the current one (attended transfer). */
    fun transferAttended(): Boolean = false
    fun hangup()
    /** Hang up exactly this SIP call (on screen or held/waiting); no-op if it is gone. */
    fun hangup(callId: Int) = hangup()
}
