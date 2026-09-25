package de.haphone.app.test

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color as AndroidColor
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.toArgb
import de.haphone.app.test.ring.AppearanceStore
import de.haphone.app.test.ring.DoorOpenClient
import de.haphone.app.test.ring.DoorOpenMethod
import de.haphone.app.test.ring.DoorOpenOutcome
import de.haphone.app.test.ring.DoorSlideState
import de.haphone.app.test.ring.DoorSlideTexts
import de.haphone.app.test.ring.NwColors
import de.haphone.app.test.ring.RingActions
import de.haphone.app.test.ring.RingInput
import de.haphone.app.test.ring.RingLayout
import de.haphone.app.test.ring.RingLayouts
import de.haphone.app.test.ring.RingScreen
import de.haphone.app.test.ring.RingVariant
import de.haphone.app.test.ring.isDraggable
import java.lang.ref.WeakReference
import java.time.LocalTime

/**
 * Native ringing screen for both push-woken and SIP-registered incoming calls.
 * Kept as a plain ComponentActivity (not Flutter) so a cold/locked start never
 * waits on the Dart engine. For door stations it shows the early-media video
 * (SIP 183) live before the call is answered; audio stays disconnected until
 * the user taps Annehmen. Hands off to the Flutter active-call screen after that.
 * Layout ("Nachtwache" stage 3) lives in ring/RingScreen.kt, its decisions in
 * ring/RingLayout.kt and ring/SlideToOpen.kt (JVM-tested). The door slider opens via
 * the PBX webhook without answering, or answers and sends the DTMF code.
 */
class IncomingCallActivity : ComponentActivity() {

    private val app get() = application as HAPhoneTestApplication

    private val main = Handler(Looper.getMainLooper())
    private var slideState by mutableStateOf<DoorSlideState>(DoorSlideState.Idle)
    private var keyguardLocked by mutableStateOf(false)

    /** Answered/declined from here: later taps and late webhook results are ignored. */
    private var handled = false

    /** The SIP call this screen rings for; null for a push-announced call without INVITE yet. */
    private var sipCallId: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        current = WeakReference(this)
        ownsVideoSurface = true
        val callId = intent.getStringExtra(EXTRA_CALL_ID).orEmpty()
        sipCallId = sipCallIdOf(intent)

        when (intent.getStringExtra(EXTRA_ACTION)) {
            ACTION_ANSWER -> { answer(); return }
            ACTION_DECLINE -> { decline(); return }
        }
        // The call may have ended between posting the intent and now (caller gave up,
        // answered elsewhere): no ghost ringing screen.
        if (finishIfNotRinging()) return
        // Backstop for the ring limit in IncomingCallFlow (e.g. the flow's timer was lost).
        main.postDelayed({ if (!handled && !isFinishing) finishIfNotRinging(force = true) }, IncomingCallFlow.RING_TIMEOUT_MS + 5_000L)

        keyguardLocked = isKeyguardLocked()
        val doorCode = app.doorCodes.forNumber(callId)
        val doorActions = app.doorActions.labelsFor(callId)
        val input = RingInput(
            callType = intent.getStringExtra(EXTRA_CALL_TYPE),
            number = callId,
            callerName = intent.getStringExtra(EXTRA_CALLER_NAME).orEmpty(),
            doorCode = doorCode,
            doorOpenRemote = app.doorCodes.hasOpenRemote(callId),
            doorActions = doorActions,
            keyguardLocked = false,
        )
        val meta = RingLayouts.meta(callId, LocalTime.now())
        val baseLayout = RingLayouts.of(input)
        // In-app "Erscheinungsbild" (default Dunkel), not the system's night mode.
        val dark = AppearanceStore.isDark(this)
        val colors = if (dark) NwColors.Dark else NwColors.Light
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(colors.ground.toArgb()))
        val themed = if (dark) {
            SystemBarStyle.dark(AndroidColor.TRANSPARENT)
        } else {
            SystemBarStyle.light(AndroidColor.TRANSPARENT, AndroidColor.TRANSPARENT)
        }
        // The door screen is a dark picture in any theme: light status bar icons.
        enableEdgeToEdge(
            statusBarStyle = if (baseLayout.variant == RingVariant.DOOR) SystemBarStyle.dark(AndroidColor.TRANSPARENT) else themed,
            navigationBarStyle = themed,
        )
        val actions = RingActions(
            onAnswer = { haptic(); answer() },
            onDecline = { haptic(); decline() },
            onSlideOpen = { onSlideOpen(baseLayout, callId, doorCode) },
            onDoorAction = { index ->
                app.runDoorAction(callId, index) { error ->
                    if (isFinishing || isDestroyed) return@runDoorAction
                    android.widget.Toast.makeText(
                        this, error ?: "${doorActions[index]}: erledigt", android.widget.Toast.LENGTH_SHORT,
                    ).show()
                }
            },
            ownsVideoSurface = { ownsVideoSurface },
        )

        setContent {
            MaterialTheme {
                RingScreen(baseLayout.copy(showLockedChip = keyguardLocked), meta, slideState, actions, colors)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (!handled && finishIfNotRinging()) return
        keyguardLocked = isKeyguardLocked()
    }

    /** Finishes when the call no longer rings (or [force]); true if it did. */
    private fun finishIfNotRinging(force: Boolean = false): Boolean {
        if (!force && app.incoming.isRinging(sipCallId)) return false
        android.util.Log.i("IncomingCallActivity", "call ${sipCallId ?: "(push)"} no longer ringing, closing ringing screen")
        handled = true
        ownsVideoSurface = false
        finish()
        return true
    }

    /** API 26 ignores the manifest's showWhenLocked/turnScreenOn (added in 27). */
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    private fun isKeyguardLocked(): Boolean =
        (getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked == true

    /** Slider released past 85 % (or the TalkBack action "Tür öffnen"). */
    private fun onSlideOpen(layout: RingLayout, number: String, doorCode: String) {
        if (handled || !slideState.isDraggable) return
        main.removeCallbacksAndMessages(RESET_TOKEN)
        when (layout.openMethod) {
            DoorOpenMethod.WEBHOOK -> openByWebhook(number)
            DoorOpenMethod.DTMF -> {
                // Door stations only take DTMF in an answered call: answer, the code follows
                // once media is up (pending-DTMF), and the call screen takes over.
                slideState = DoorSlideState.Busy(DoorSlideTexts.ANSWERING)
                haptic()
                main.postDelayed({ if (!handled && !isFinishing) openDoorByDtmf(doorCode) }, DTMF_FEEDBACK_MS)
            }
            DoorOpenMethod.NONE -> Unit
        }
    }

    /** Opens without answering; the screen keeps ringing so the user can still answer or decline. */
    private fun openByWebhook(number: String) {
        slideState = DoorSlideState.Busy(DoorSlideTexts.OPENING)
        val auth = app.getDeviceAuth()
        Thread {
            val outcome = DoorOpenClient.open(
                auth["apiHost"].orEmpty(), auth["deviceId"].orEmpty(), auth["deviceToken"].orEmpty(), number,
            )
            main.post {
                if (isFinishing || isDestroyed || handled) return@post
                val message = outcome.message
                if (outcome == DoorOpenOutcome.OPENED || message == null) {
                    slideState = DoorSlideState.Opened
                    doorOpenedHaptic()
                    resetSliderAfter(DoorSlideTexts.OPENED_MS)
                } else {
                    slideState = DoorSlideState.Failed(message)
                    resetSliderAfter(DoorSlideTexts.FAILED_MS)
                }
            }
        }.start()
    }

    private fun resetSliderAfter(delayMs: Long) {
        main.removeCallbacksAndMessages(RESET_TOKEN)
        androidx.core.os.HandlerCompat.postDelayed(main, { slideState = DoorSlideState.Idle }, RESET_TOKEN, delayMs)
    }

    private fun haptic() {
        window.decorView.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
    }

    /** Nachtwache: double pulse for "Tür geöffnet". */
    private fun doorOpenedHaptic() {
        val strong = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS
        window.decorView.performHapticFeedback(strong)
        main.postDelayed({ if (!isDestroyed) window.decorView.performHapticFeedback(strong) }, 140)
    }

    // singleTop: the notification's Annehmen/Ablehnen actions arrive here while the screen is open.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sipCallIdOf(intent)?.let { sipCallId = it }
        when (intent.getStringExtra(EXTRA_ACTION)) {
            ACTION_ANSWER -> answer()
            ACTION_DECLINE -> decline()
        }
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        if (current?.get() === this) current = null
        super.onDestroy()
    }

    private fun answer() {
        if (handled) return
        handled = true
        // From here on the Flutter call screen owns the video; a late surfaceChanged of this
        // dying SurfaceView must not steal the window back (it would stay black).
        ownsVideoSurface = false
        // One idempotent, exception-safe path (also used by the notification action and
        // Telecom's onAnswer); it tells Telecom and marks the local answer itself.
        if (app.incoming.answer(sipCallId, fromTelecom = false) == IncomingCallFlow.AnswerResult.FAILED) {
            finish()
            return
        }
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                putExtra("route", "active_call")
                // This screen lives in its own task (manifest taskAffinity): bring MainActivity's
                // own task forward instead of stacking a second MainActivity on top of this one.
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
        )
        finish()
    }

    /** Door stations only accept DTMF in an answered call: answer, then send the code once connected. */
    private fun openDoorByDtmf(code: String) {
        app.sipCallController.queueDtmfOnConnect(code)
        answer()
    }

    private fun decline() {
        if (handled) return
        handled = true
        ownsVideoSurface = false
        app.incoming.decline(sipCallId)
        finish()
    }

    companion object {
        const val EXTRA_CALL_ID = "callId"
        const val EXTRA_CALL_TYPE = "callType"
        const val EXTRA_CALLER_NAME = "callerName"
        const val EXTRA_ACTION = "action"
        const val EXTRA_SIP_CALL_ID = "sipCallId"
        const val ACTION_ANSWER = "answer"
        const val ACTION_DECLINE = "decline"

        private var current: WeakReference<IncomingCallActivity>? = null
        private val RESET_TOKEN = Any()
        private const val DTMF_FEEDBACK_MS = 350L

        /** Main thread only. False once the call was answered/declined from this screen. */
        var ownsVideoSurface = false
            private set

        fun intent(
            context: Context,
            callId: String,
            callType: String,
            callerName: String?,
            action: String? = null,
            sipCallId: Int? = null,
        ) = Intent(context, IncomingCallActivity::class.java)
            .putExtra(EXTRA_CALL_ID, callId)
            .putExtra(EXTRA_CALL_TYPE, callType)
            .putExtra(EXTRA_CALLER_NAME, callerName)
            .putExtra(EXTRA_ACTION, action)
            .putExtra(EXTRA_SIP_CALL_ID, sipCallId ?: NO_SIP_CALL)

        private const val NO_SIP_CALL = Int.MIN_VALUE

        private fun sipCallIdOf(intent: Intent): Int? =
            intent.getIntExtra(EXTRA_SIP_CALL_ID, NO_SIP_CALL).takeIf { it != NO_SIP_CALL }

        /** Caller hung up / someone else answered before we did. */
        fun finishIfShowing() {
            current?.get()?.finish()
        }
    }
}
