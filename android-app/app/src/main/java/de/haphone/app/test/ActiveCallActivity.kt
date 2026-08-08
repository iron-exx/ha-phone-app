package de.haphone.app.test

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.telecom.CallEndpointCompat
import de.haphone.app.test.sip.DialedNumberState
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

class ActiveCallActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sipCallController = (application as HAPhoneTestApplication).sipCallController
        // Populated by CallRegistration.reportIncomingCall AND
        // reportOutgoingCall (Plan 04's Blocker fix) -- real for both
        // call directions, not just incoming. Both callers of this
        // Activity (IncomingCallActivity.onAnswer, OutgoingCallActivity's
        // onCall) navigate here only AFTER that registration's
        // onRegistered lambda has already run, so this one-time read is
        // safe (see Plan 06 Task 2's race-condition fix for the outgoing
        // path).
        val callControlScope = (application as HAPhoneTestApplication).currentCallControlScope
        // Explicit suspend-typed local val (Rule 1 fix, compile error against
        // the real androidx.core.telecom 1.0.0 API): a lambda literal passed
        // directly as a named argument at this call site was not being
        // inferred as `suspend` by the compiler ("should be called only from
        // a coroutine or another suspend function"), even though
        // ActiveCallScreen's parameter is declared `suspend (CallEndpointCompat)
        // -> Unit`. Binding it to an explicitly `suspend`-typed local first
        // forces the expected type before the body is analyzed.
        val requestEndpointChange: suspend (CallEndpointCompat) -> Unit = { endpoint ->
            callControlScope?.requestEndpointChange(endpoint)
            Unit
        }
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    ActiveCallScreen(
                        onMute = { muted -> sipCallController.mute(muted) },
                        onHold = { onHold -> sipCallController.hold(onHold) },
                        // Suspend lambda -- callControlScope.requestEndpointChange
                        // is itself a suspend fun; ActiveCallScreen launches this
                        // from a rememberCoroutineScope() at the actual tap site.
                        onRequestEndpointChange = requestEndpointChange,
                        // Rule 1 fix: androidx.core.telecom 1.0.0's
                        // CallControlScope.availableEndpoints is a plain
                        // Flow<List<CallEndpointCompat>>, not a StateFlow --
                        // confirmed by the real compiled API, not the plan's
                        // illustrative StateFlow snippet.
                        availableEndpoints = callControlScope?.availableEndpoints,
                        onSendDtmf = { digit -> sipCallController.sendDtmf(digit.toString()) },
                        onTransfer = { target -> sipCallController.transfer(target) },
                        onEndCall = {
                            sipCallController.hangup()
                            finish()
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActiveCallScreen(
    onMute: (Boolean) -> Unit,
    onHold: (Boolean) -> Unit,
    onRequestEndpointChange: suspend (CallEndpointCompat) -> Unit,
    availableEndpoints: Flow<List<CallEndpointCompat>>?,
    onSendDtmf: (Char) -> Unit,
    onTransfer: (String) -> Unit,
    onEndCall: () -> Unit,
) {
    var muted by remember { mutableStateOf(false) }
    var onHoldState by remember { mutableStateOf(false) }
    var showKeypad by remember { mutableStateOf(false) }
    var showTransfer by remember { mutableStateOf(false) }
    var showRoutingMenu by remember { mutableStateOf(false) }
    val transferState = remember { DialedNumberState() }
    // Compile-error fix: DropdownMenuItem's onClick is not a suspend
    // context, but onRequestEndpointChange IS suspend (it wraps
    // CallControlScope.requestEndpointChange) -- launch it here rather
    // than calling it directly.
    val coroutineScope = rememberCoroutineScope()
    // Real endpoint list, never a stub -- collects the live
    // CallControlScope.availableEndpoints Flow (empty fallback only if no
    // call is active yet, e.g. screen shown before onRegistered).
    // Rule 1 fix: availableEndpoints is a plain Flow (not StateFlow) on the
    // real androidx.core.telecom 1.0.0 API, so collectAsState needs an
    // explicit initial value.
    val endpoints by (availableEndpoints ?: remember { MutableStateFlow(emptyList()) })
        .collectAsState(initial = emptyList())

    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Text("In call", fontSize = 28.sp)

        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Button(onClick = { muted = !muted; onMute(muted) }) { Text(if (muted) "Unmute" else "Mute") }
            Button(onClick = { onHoldState = !onHoldState; onHold(onHoldState) }) { Text(if (onHoldState) "Unhold" else "Hold") }
            Box {
                // Real, functional endpoint picker -- lists every entry
                // in CallControlScope.availableEndpoints; tapping one
                // launches a coroutine to call the suspend
                // onRequestEndpointChange(endpoint) directly, never
                // AudioManager. Works for both MO and MT calls per Plan
                // 04's Blocker fix.
                Button(onClick = { showRoutingMenu = true }) { Text("Audio Routing") }
                DropdownMenu(expanded = showRoutingMenu, onDismissRequest = { showRoutingMenu = false }) {
                    endpoints.forEach { endpoint ->
                        DropdownMenuItem(
                            text = { Text(endpoint.name.toString()) },
                            onClick = {
                                coroutineScope.launch { onRequestEndpointChange(endpoint) }
                                showRoutingMenu = false
                            },
                        )
                    }
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Button(onClick = { showKeypad = true }) { Text("Keypad") }
            Button(onClick = { showTransfer = true }) { Text("Transfer") }
        }

        Button(
            onClick = onEndCall,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
        ) { Text("End Call") }
    }

    if (showKeypad) {
        ModalBottomSheet(onDismissRequest = { showKeypad = false }) {
            Column(modifier = Modifier.padding(24.dp)) {
                Text("Keypad")
                DialpadComposable(onDigit = { digit -> onSendDtmf(digit) })
            }
        }
    }

    if (showTransfer) {
        ModalBottomSheet(onDismissRequest = { showTransfer = false }) {
            Column(modifier = Modifier.padding(24.dp)) {
                Text("Transfer to")
                Text(transferState.current.ifEmpty { "Enter extension" }, fontSize = 28.sp)
                DialpadComposable(onDigit = { transferState.append(it) })
                Button(onClick = { onTransfer(transferState.current); showTransfer = false }) {
                    Text("Transfer")
                }
            }
        }
    }
}
