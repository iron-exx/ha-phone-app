package de.haphone.app.test

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class TestFcmService : FirebaseMessagingService() {
    private val verifierPublicKeyHex = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"

    override fun onMessageReceived(message: RemoteMessage) {
        val data: Map<String, Any> = message.data.mapValues { (key, value) ->
            if (key == "expires_at" || key == "issued_at" || key == "v") value.toIntOrNull() ?: value else value
        }
        val isValid = EnvelopeVerifier.verify(data, verifierPublicKeyHex)
        val isExpired = EnvelopeVerifier.isExpired(data)

        val callType = data["call_type"] as? String ?: "audio"
        val callId = data["call_id"] as? String ?: java.util.UUID.randomUUID().toString()

        if (isValid && !isExpired) {
            // Fix: this used to go straight to CallNotificationBuilder.show()
            // without ever telling Android Telecom about the call.
            // CallRegistration.reportIncomingCall() had zero call sites
            // anywhere in the app, so HAPhoneTestApplication.currentCallControlScope
            // was never populated for inbound calls, and
            // IncomingCallActivity.onAnswer's real SIP-answer step silently
            // no-op'd even when the user tapped Answer. Reporting the call
            // here is what actually makes it answerable.
            val app = applicationContext as HAPhoneTestApplication
            app.callRegistration.reportIncomingCall(callId) {
                // onRegistered: CallRegistration already stashed the live
                // CallControlScope into app.currentCallControlScope before
                // this runs; nothing further needed here until the user
                // taps Answer (IncomingCallActivity) or Decline.
            }
            CallNotificationBuilder.show(applicationContext, callId, callType, isValid, isExpired)
        } else {
            Log.w("HAPhoneTest", "FCM call REJECTED: callId=$callId, valid=$isValid, expired=$isExpired")
        }
        Log.i("HAPhoneTest", "FCM call received: callId=$callId, valid=$isValid, expired=$isExpired")
    }
}
