package de.haphone.app.test

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

        val registration = CallRegistration(applicationContext)
        registration.registerApp()
        val callId = data["call_id"] as? String ?: java.util.UUID.randomUUID().toString()

        // MANDATORY per Pitfall 2: always produce a visible notification, regardless
        // of signature/expiry outcome -- never silently drop a call-type FCM message.
        registration.reportIncomingCall(callId) {
            CallNotificationBuilder.show(applicationContext, callId, isValid, isExpired)
        }
    }
}
