package de.haphone.app.test

import android.os.Bundle
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

/**
 * Minimal placeholder incoming-call screen (D-05/D-06): shows the fixed
 * "HA-Phone Testanruf" caller placeholder, full-screen, with Answer/Decline
 * buttons that simply finish() the activity. No real call/SIP logic exists
 * in Phase 1.
 */
class IncomingCallActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val callId = intent.getStringExtra("callId").orEmpty()
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    IncomingCallScreen(
                        callId = callId,
                        onAnswer = { finish() },
                        onDecline = { finish() },
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
