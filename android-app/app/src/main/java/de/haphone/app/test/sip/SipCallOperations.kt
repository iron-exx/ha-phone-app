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
    fun makeCall(uri: String)
    fun answer(): Boolean // false = SIP negotiation failed
    fun hold(onHold: Boolean)
    fun mute(muted: Boolean)
    fun transfer(uri: String)
    fun sendDtmf(digit: String)
    fun hangup()
}
