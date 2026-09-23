package de.haphone.app.test

import android.telecom.DisconnectCause
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
            CallNotificationBuilder.show(applicationContext, callId, callType, isValid, isExpired)
        } else {
            Log.w("HAPhoneTest", "FCM call REJECTED: callId=$callId, valid=$isValid, expired=$isExpired")
        }
        Log.i("HAPhoneTest", "FCM call received: callId=$callId, valid=$isValid, expired=$isExpired")
    }
}
