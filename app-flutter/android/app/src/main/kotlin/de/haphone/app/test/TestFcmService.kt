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
            // onMessageReceived runs on an FCM worker thread; PJSIP, Telecom bookkeeping and
            // the ringtone are main-thread only. IncomingCallFlow reports the call to Telecom,
            // rings, and disconnects it as MISSED after the ring limit.
            val app = applicationContext as HAPhoneTestApplication
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                runCatching { app.incoming.onPushCall(callId, callType) }
                    .onFailure { Log.e("HAPhoneTest", "push call $callId could not be shown", it) }
            }
        } else {
            Log.w("HAPhoneTest", "FCM call REJECTED: callId=$callId, valid=$isValid, expired=$isExpired")
        }
        Log.i("HAPhoneTest", "FCM call received: callId=$callId, valid=$isValid, expired=$isExpired")
    }
}
