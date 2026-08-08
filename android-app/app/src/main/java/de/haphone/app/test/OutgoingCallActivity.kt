package de.haphone.app.test

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.haphone.app.test.sip.DialedNumberState

// NOTE: no local domain constant here -- the real HA-Phone host (from
// Plan 01's checkpoint output, substituted per Plan 04's fix into
// HAPhoneTestApplication.sipCallController) is owned centrally and
// reached via sipCallController.makeCall() below; it is never
// duplicated or hardcoded in this file.

class OutgoingCallActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as HAPhoneTestApplication
        val sipCallController = app.sipCallController
        // Blocker fix: outgoing calls must register with Telecom the same
        // way incoming calls do (CallRegistration.reportOutgoingCall,
        // DIRECTION_OUTGOING, added in Plan 04) -- otherwise
        // CallControlScope.availableEndpoints stays empty for MO calls
        // and Audio Routing (CALL-01) cannot work.
        val callRegistration = CallRegistration(applicationContext, sipCallController)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val state = remember { DialedNumberState() }
                    OutgoingCallScreen(
                        state = state,
                        onCall = {
                            val digits = state.current
                            // Race-condition fix (checker warning, iteration 3):
                            // navigate to ActiveCallActivity ONLY from inside
                            // reportOutgoingCall's onRegistered lambda, after
                            // makeCall -- reportOutgoingCall registers
                            // asynchronously (a coroutine in CallRegistration.kt),
                            // so calling startActivity/finish() synchronously
                            // right here (as a prior revision did) could run
                            // before that coroutine ever stashes
                            // currentCallControlScope, leaving Audio Routing
                            // permanently empty for this call. Moving navigation
                            // inside the lambda guarantees the scope is already
                            // populated by the time ActiveCallActivity.onCreate
                            // reads it.
                            callRegistration.reportOutgoingCall(callId = digits) {
                                // `this` = the live CallControlScope Telecom just
                                // reported; reportOutgoingCall already stashed it
                                // into app.currentCallControlScope for
                                // ActiveCallActivity's Audio Routing to read,
                                // BEFORE this lambda body runs.
                                // The SIP INVITE fires here, only after Telecom
                                // has actually reported the call.
                                sipCallController.makeCall(digits)
                                startActivity(Intent(this@OutgoingCallActivity, ActiveCallActivity::class.java))
                                finish()
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun OutgoingCallScreen(state: DialedNumberState, onCall: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Text(
            text = state.current.ifEmpty { "Enter extension" },
            fontSize = 28.sp,
        )
        DialpadComposable(onDigit = { state.append(it) })
        Button(onClick = onCall, enabled = state.current.isNotEmpty()) {
            Text("Call")
        }
    }
}
