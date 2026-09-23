package de.haphone.app.test

import io.flutter.plugin.common.EventChannel

/**
 * Bridges native registration/call-state changes to Flutter over
 * EventChannel("de.haphone.app.test/call_events"). [sink] is only non-null
 * while Dart is actively listening (between StreamHandler onListen/
 * onCancel, wired in SipChannelHandler) -- emit* calls are no-ops
 * otherwise rather than buffering, matching the EventChannel contract.
 *
 * Phase 1 scope: wired from SipCallController.register()/unregister() and
 * CallRegistration's onRegistered/onDisconnect lambdas (coarse call
 * lifecycle only). Finer-grained PJSIP-level state (exact SIP response
 * codes from PjsuaEndpointHolder's HAPhoneCall.onCallState()) is not
 * wired yet -- left for a follow-up once the outgoing-call demo milestone
 * is proven, so as not to touch the PJSIP-adjacent code blind.
 */
object CallEventBus {
    var sink: EventChannel.EventSink? = null

    // PJSIP callbacks arrive on its worker thread; EventSink must only be used on the main thread.
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    private fun post(event: Map<String, Any?>) {
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) sink?.success(event)
        else mainHandler.post { sink?.success(event) }
    }

    fun emitRegistrationState(state: String, code: Int? = null) {
        post(mapOf("type" to "registrationState", "state" to state, "code" to code))
    }

    fun emitCallState(callId: String, direction: String, state: String, disconnectReason: String? = null) {
        post(
            mapOf(
                "type" to "callState",
                "callId" to callId,
                "direction" to direction,
                "state" to state,
                "disconnectReason" to disconnectReason,
            ),
        )
    }
}
