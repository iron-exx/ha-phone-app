package de.haphone.app.test

import android.content.Intent
import android.os.Bundle
import android.telecom.DisconnectCause
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * Incoming-call screen shown from CallNotificationBuilder's CallStyle
 * notification (both its full-screen intent and its Answer/Decline
 * actions, per D-05/D-06). Answer/Decline are the app's real, genuine
 * user-answer signal (CR-01's invariant is "never call sipOps.answer()
 * except in direct response to a real user tap" -- a Button onClick
 * here satisfies that exactly as much as Telecom's own onAnswer callback
 * would).
 *
 * Code review CR-3 fix: this previously just navigated to
 * ActiveCallActivity / finish()-ed without ever touching
 * CallControlScope or SipCallController, so the underlying SIP dialog
 * stayed at 180 Ringing (Answer) or kept ringing indefinitely (Decline)
 * regardless of what the user tapped here. Reaches the CallControlScope
 * CallRegistration.reportIncomingCall already stashed in
 * HAPhoneTestApplication.currentCallControlScope to actually drive the
 * SIP 200 OK / hangup, mirroring CallRegistration.kt's own
 * liveScope?.let { sipCallController.answer(it) } call shape.
 */
class IncomingCallActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val callId = intent.getStringExtra("callId").orEmpty()
        val app = application as HAPhoneTestApplication
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    IncomingCallScreen(
                        callId = callId,
                        onAnswer = {
                            app.currentCallControlScope?.let { scope ->
                                app.sipCallController.answer(scope)
                            }
                            startActivity(Intent(this, ActiveCallActivity::class.java))
                            finish()
                        },
                        onDecline = {
                            app.currentCallControlScope?.let { scope ->
                                scope.launch { scope.disconnect(DisconnectCause(DisconnectCause.LOCAL)) }
                            }
                            app.sipCallController.hangup()
                            finish()
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun IncomingCallScreen(callId: String, onAnswer: () -> Unit, onDecline: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("HA-Phone Testanruf")
        Text("callId=$callId")
        Row(
            modifier = Modifier.padding(top = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Button(onClick = onDecline) { Text("Decline") }
            Button(onClick = onAnswer) { Text("Answer") }
        }
    }
}
