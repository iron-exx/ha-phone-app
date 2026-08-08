package de.haphone.app.test

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : ComponentActivity() {
    private val fcmTokenState = mutableStateOf("Fetching FCM token...")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Fetch the FCM registration token on launch. Displayed (selectable) below so the
        // developer can copy it directly for `tools/push_trigger.py --device-token <token>`
        // without needing to dig through `adb logcat`; the log line is kept as a fallback.
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val token = task.result
                Log.i("HAPhoneTest", "FCM token: $token")
                fcmTokenState.value = token
            } else {
                Log.w("HAPhoneTest", "FCM token fetch failed", task.exception)
                fcmTokenState.value = "FCM token fetch failed: ${task.exception?.message}"
            }
        }

        setContent {
            val fcmToken by fcmTokenState
            MaterialTheme {
                Surface {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text("HA-Phone Test")
                        SelectionContainer {
                            Text(fcmToken)
                        }
                        Button(onClick = { startActivity(Intent(this@MainActivity, OutgoingCallActivity::class.java)) }) {
                            Text("Dial")
                        }
                    }
                }
            }
        }
    }
}
