package de.haphone.app.test

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telecom.DisconnectCause
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.telecom.CallAttributesCompat
import de.haphone.app.test.sip.VideoSurfaceBinder
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference

/**
 * Native ringing screen for both push-woken and SIP-registered incoming calls.
 * Kept as a plain ComponentActivity (not Flutter) so a cold/locked start never
 * waits on the Dart engine. For door stations it shows the early-media video
 * (SIP 183) live before the call is answered; audio stays disconnected until
 * the user taps Annehmen. Hands off to the Flutter active-call screen after that.
 */
class IncomingCallActivity : ComponentActivity() {

    private val app get() = application as HAPhoneTestApplication

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME).orEmpty()
        val callId = intent.getStringExtra(EXTRA_CALL_ID).orEmpty()
        val isVideo = intent.getStringExtra(EXTRA_CALL_TYPE) in setOf("video", "door")

        when (intent.getStringExtra(EXTRA_ACTION)) {
            ACTION_ANSWER -> { answer(); return }
            ACTION_DECLINE -> { decline(); return }
        }

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = Color(0xFF101418)) {
                    IncomingCallScreen(
                        callerName = callerName.ifBlank { callId },
                        callerNumber = callId,
                        showVideo = isVideo,
                        onAnswer = ::answer,
                        onDecline = ::decline,
                    )
                }
            }
        }
    }

    // singleTop: the notification's Annehmen/Ablehnen actions arrive here while the screen is open.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        when (intent.getStringExtra(EXTRA_ACTION)) {
            ACTION_ANSWER -> answer()
            ACTION_DECLINE -> decline()
        }
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        super.onDestroy()
    }

    private fun answer() {
        val scope = app.currentCallControlScope
        // Tell Telecom we answered from our own UI (if it has registered the call yet),
        // then send the SIP 200 OK either way.
        scope?.launch { runCatching { scope.answer(CallAttributesCompat.CALL_TYPE_AUDIO_CALL) } }
        app.sipCallController.answer(scope)
        CallNotificationBuilder.cancel(this)
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                putExtra("route", "active_call")
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
        )
        finish()
    }

    private fun decline() {
        runCatching { app.sipCallController.hangup() }
        app.releaseTelecomCall(DisconnectCause.LOCAL)
        CallNotificationBuilder.cancel(this)
        VideoSurfaceBinder.reset()
        finish()
    }

    companion object {
        const val EXTRA_CALL_ID = "callId"
        const val EXTRA_CALL_TYPE = "callType"
        const val EXTRA_CALLER_NAME = "callerName"
        const val EXTRA_ACTION = "action"
        const val ACTION_ANSWER = "answer"
        const val ACTION_DECLINE = "decline"

        private var current: WeakReference<IncomingCallActivity>? = null

        fun intent(context: Context, callId: String, callType: String, callerName: String?, action: String? = null) =
            Intent(context, IncomingCallActivity::class.java)
                .putExtra(EXTRA_CALL_ID, callId)
                .putExtra(EXTRA_CALL_TYPE, callType)
                .putExtra(EXTRA_CALLER_NAME, callerName)
                .putExtra(EXTRA_ACTION, action)

        /** Caller hung up / someone else answered before we did. */
        fun finishIfShowing() {
            current?.get()?.finish()
        }
    }
}

@Composable
private fun IncomingCallScreen(
    callerName: String,
    callerNumber: String,
    showVideo: Boolean,
    onAnswer: () -> Unit,
    onDecline: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(32.dp))
        Text("Eingehender Anruf", color = Color(0xFFB0BEC5), fontSize = 16.sp)
        Text(callerName, color = Color.White, fontSize = 30.sp, modifier = Modifier.padding(top = 8.dp))
        if (callerName != callerNumber && callerNumber.isNotBlank()) {
            Text(callerNumber, color = Color(0xFFB0BEC5), fontSize = 18.sp)
        }
        Spacer(Modifier.height(24.dp))
        if (showVideo) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(4f / 3f)
                    .background(Color.Black),
                contentAlignment = Alignment.Center,
            ) {
                Text("Video wird geladen…", color = Color(0xFF78909C))
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { ctx ->
                        SurfaceView(ctx).apply {
                            holder.addCallback(object : SurfaceHolder.Callback {
                                override fun surfaceCreated(h: SurfaceHolder) {}
                                override fun surfaceChanged(h: SurfaceHolder, format: Int, w: Int, hgt: Int) {
                                    VideoSurfaceBinder.setSurface(h.surface)
                                }
                                override fun surfaceDestroyed(h: SurfaceHolder) {
                                    VideoSurfaceBinder.setSurface(null)
                                }
                            })
                        }
                    },
                )
            }
        }
        Spacer(Modifier.weight(1f))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 32.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            RoundCallButton("Ablehnen", Color(0xFFD32F2F), onDecline)
            RoundCallButton("Annehmen", Color(0xFF2E7D32), onAnswer)
        }
    }
}

@Composable
private fun RoundCallButton(label: String, color: Color, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Button(
            onClick = onClick,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(containerColor = color),
            modifier = Modifier.size(76.dp),
        ) {}
        Text(label, color = Color.White, modifier = Modifier.padding(top = 8.dp))
    }
}
