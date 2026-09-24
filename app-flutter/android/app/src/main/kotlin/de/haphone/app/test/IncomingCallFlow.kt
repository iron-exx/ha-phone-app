package de.haphone.app.test

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.telecom.DisconnectCause
import android.util.Log
import androidx.core.telecom.CallAttributesCompat
import de.haphone.app.test.calls.AnswerGuard
import de.haphone.app.test.calls.CallSession
import de.haphone.app.test.calls.RingtonePlayer
import de.haphone.app.test.sip.IncomingSipCall
import de.haphone.app.test.sip.VideoSurfaceBinder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Everything between "an incoming call rings" and "answered / declined / gone": Telecom
 * report, notification, ringing screen, ringtone, ring timeout, and the single answer
 * path shared by the ringing screen, the notification action and Telecom's onAnswer
 * (car, headset, watch). Main thread only.
 */
class IncomingCallFlow(private val app: HAPhoneTestApplication) {
    enum class AnswerResult { ANSWERED, ALREADY_ANSWERED, FAILED }

    private val guard = AnswerGuard()
    private val main = Handler(Looper.getMainLooper())

    /** The focused call that is ringing right now (ringtone), and the knocking one (beep). */
    private var ringingSipCallId: Int? = null
    private var waitingSipCallId: Int? = null

    /** A SIP INVITE rang through (PjsuaEndpointHolder posted it to main). */
    fun onIncoming(call: IncomingSipCall) {
        val number = call.number.ifBlank { "unknown" }
        val callType = if (call.hasVideo) "video" else "audio"
        when (app.calls.beginIncoming(call.callId, call.number, call.displayName, call.hasVideo)) {
            CallSession.IncomingRole.REJECT -> {
                Log.w(TAG, "third call ${call.callId} rejected")
                runCatching { app.sipCallController.hangup(call.callId) }
            }
            CallSession.IncomingRole.WAITING -> {
                // Call waiting: the Telecom call and the call screen stay; Dart shows the waiting banner.
                waitingSipCallId = call.callId
                CallNotificationBuilder.showWaiting(app, number, call.displayName)
                RingtonePlayer.startWaitingBeep(app, CallNotificationBuilder.CHANNEL_ID)
                scheduleRingTimeout(call.callId)
            }
            CallSession.IncomingRole.FOCUSED -> {
                ringingSipCallId = call.callId
                // A push may already have put this call into Telecom: take that over.
                if (app.telecom.adoptPushCall(call.callId) == null) {
                    app.callRegistration.reportIncomingCall(call.callId, number, call.displayName)
                }
                CallNotificationBuilder.show(
                    app, number, callType, isValid = true, isExpired = false,
                    callerName = call.displayName, sipCallId = call.callId,
                )
                RingtonePlayer.startRinging(app, CallNotificationBuilder.CHANNEL_ID)
                scheduleRingTimeout(call.callId)
                // The full-screen intent only fires on a locked/off screen; with the phone in
                // use it would just be a heads-up, so open the ringing screen directly.
                runCatching {
                    app.startActivity(
                        IncomingCallActivity.intent(app, number, callType, call.displayName, sipCallId = call.callId)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }.onFailure { Log.w(TAG, "could not open ringing screen", it) }
            }
        }
    }

    /** A verified FCM call push (no SIP call yet). */
    fun onPushCall(callId: String, callType: String) {
        val token = app.callRegistration.reportIncomingCall(null, callId)
        CallNotificationBuilder.show(app, callId, callType, isValid = true, isExpired = false)
        RingtonePlayer.startRinging(app, CallNotificationBuilder.CHANNEL_ID)
        main.postDelayed({
            if (app.telecom.isLive(token) && app.telecom.sipCallIdFor(token) == null && !app.telecom.isAnswered(token)) {
                Log.i(TAG, "push call $callId not answered within ${RING_TIMEOUT_MS / 1000}s -> missed")
                app.telecom.release(token, DisconnectCause.MISSED)
                if (app.calls.session.isEmpty) {
                    stopAlerting()
                    CallNotificationBuilder.cancel(app)
                    IncomingCallActivity.finishIfShowing()
                }
            }
        }, RING_TIMEOUT_MS)
    }

    /** True while [sipCallId] (or, if null, a push-announced call) still rings unanswered. */
    fun isRinging(sipCallId: Int?): Boolean {
        if (sipCallId == null) {
            return app.telecom.hasUnansweredPushCall() ||
                app.calls.session.focused?.let { it.call.state == "ringing" && !guard.isAnswered(it.callId) } == true
        }
        if (guard.isAnswered(sipCallId)) return false
        return app.calls.session.find(sipCallId)?.call?.state == "ringing"
    }

    /**
     * The one answer path. Idempotent per SIP call ([AnswerGuard]); exception-safe (a SWIG
     * exception ends the call instead of the process). [fromTelecom]: Telecom asked (car,
     * headset); otherwise our screen/notification did, and Telecom is told.
     */
    fun answer(sipCallId: Int?, fromTelecom: Boolean): AnswerResult {
        val id = sipCallId ?: app.calls.session.focused?.takeIf { it.call.direction == "incoming" }?.callId
        if (id == null) {
            // Push-announced call whose INVITE never came: nothing to answer (CR-01).
            Log.w(TAG, "answer: no SIP call to answer")
            stopAlerting()
            app.endTelecomSession(DisconnectCause.ERROR)
            return AnswerResult.FAILED
        }
        if (!guard.tryBegin(id)) {
            Log.i(TAG, "answer: call $id already answered, ignoring (fromTelecom=$fromTelecom)")
            return AnswerResult.ALREADY_ANSWERED
        }
        stopAlerting()
        // Telecom may report this answer back through onAnswer; that must not run the
        // "answered in the car" hand-off (see HAPhoneTestApplication.onAnsweredRemotely).
        if (!fromTelecom) app.markAnsweredLocally()
        val ok = runCatching { app.sipCallController.answer(id) }
            .onFailure { Log.e(TAG, "SIP answer of call $id threw", it) }
            .getOrDefault(false)
        if (!ok) {
            Log.w(TAG, "answer of call $id failed -> ending it")
            failAnswer(id)
            return AnswerResult.FAILED
        }
        val token = app.telecom.tokenFor(id)
        if (token != null) {
            app.telecom.markAnswered(token)
            if (!fromTelecom) {
                // Not registered yet? CallRegistration answers it as soon as it is.
                app.telecom.scopeFor(token)?.let { scope ->
                    scope.launch {
                        runCatching { scope.answer(CallAttributesCompat.CALL_TYPE_AUDIO_CALL) }
                            .onFailure { if (it is CancellationException) throw it else Log.w(TAG, "Telecom answer failed", it) }
                    }
                }
            }
        }
        CallNotificationBuilder.cancel(app)
        SipService.setInCall(true)
        return AnswerResult.ANSWERED
    }

    private fun failAnswer(id: Int) {
        runCatching { app.sipCallController.hangup(id) }
            .onFailure { Log.w(TAG, "hangup after failed answer threw", it) }
        app.telecom.releaseForSipCall(id, DisconnectCause.ERROR)
        CallNotificationBuilder.cancel(app)
        IncomingCallActivity.finishIfShowing()
    }

    /** Ablehnen on the ringing screen or the notification. */
    fun decline(sipCallId: Int?) {
        stopAlerting()
        val id = sipCallId ?: app.calls.session.focused?.takeIf { it.call.direction == "incoming" }?.callId
        if (id != null) {
            runCatching { app.sipCallController.hangup(id) }
                .onFailure { Log.w(TAG, "decline: SIP hangup threw", it) }
        }
        // With a second call the Telecom call stays: that call is still up.
        if (app.calls.session.other == null) app.releaseTelecomCall(DisconnectCause.LOCAL)
        CallNotificationBuilder.cancel(app)
        VideoSurfaceBinder.reset()
    }

    /** Call waiting: Annehmen (holds the current call). Swaps only if the 200 OK went out. */
    fun answerWaiting(): Boolean {
        CallNotificationBuilder.cancelWaiting(app)
        RingtonePlayer.stopWaitingBeep()
        val ok = runCatching { app.sipCallController.answerWaiting() }
            .onFailure { Log.e(TAG, "answerWaiting threw", it) }
            .getOrDefault(false)
        if (!ok) return false
        waitingSipCallId?.let { guard.tryBegin(it) }
        waitingSipCallId = null
        SipService.setInCall(true)
        return app.calls.acceptWaiting()
    }

    fun rejectWaiting() {
        CallNotificationBuilder.cancelWaiting(app)
        RingtonePlayer.stopWaitingBeep()
        runCatching { app.sipCallController.rejectWaiting() }
            .onFailure { Log.w(TAG, "rejectWaiting threw", it) }
    }

    /** A SIP call ended (remote cancel, answered elsewhere, hangup, failure). */
    fun onCallEnded(sipCallId: Int) {
        guard.forget(sipCallId)
        if (sipCallId == ringingSipCallId) {
            ringingSipCallId = null
            RingtonePlayer.stop()
        }
        if (sipCallId == waitingSipCallId) {
            waitingSipCallId = null
            RingtonePlayer.stopWaitingBeep()
        }
        main.removeCallbacksAndMessages(timeoutToken(sipCallId))
    }

    /** SIP CONFIRMED: whatever answered it, nothing rings for it any more. */
    fun onConfirmed(sipCallId: Int) {
        if (sipCallId == ringingSipCallId) {
            ringingSipCallId = null
            RingtonePlayer.stop()
        }
        main.removeCallbacksAndMessages(timeoutToken(sipCallId))
    }

    /** Stops ringtone, vibration and waiting beep (every end path). */
    fun stopAlerting() {
        RingtonePlayer.stop()
        ringingSipCallId?.let { main.removeCallbacksAndMessages(timeoutToken(it)) }
        ringingSipCallId = null
    }

    /** Hard ring limit: some PBX setups never CANCEL, and a ghost ring must not go on forever. */
    private fun scheduleRingTimeout(sipCallId: Int) {
        val token = timeoutToken(sipCallId)
        main.removeCallbacksAndMessages(token)
        androidx.core.os.HandlerCompat.postDelayed(main, {
            val state = app.calls.session.find(sipCallId)?.call?.state
            if (guard.isAnswered(sipCallId) || (state != "ringing" && state != "waiting")) return@postDelayed
            Log.i(TAG, "call $sipCallId rang ${RING_TIMEOUT_MS / 1000}s unanswered -> hang up")
            if (sipCallId == waitingSipCallId) {
                rejectWaiting()
                return@postDelayed
            }
            stopAlerting()
            runCatching { app.sipCallController.hangup(sipCallId) }
                .onFailure { Log.w(TAG, "ring timeout hangup threw", it) }
            app.telecom.releaseForSipCall(sipCallId, DisconnectCause.MISSED)
            CallNotificationBuilder.cancel(app)
            IncomingCallActivity.finishIfShowing()
        }, token, RING_TIMEOUT_MS)
    }

    /** Stable per-id token for Handler callbacks (boxed Ints outside the cache are not identical). */
    private val timeoutTokens = mutableMapOf<Int, Any>()
    private fun timeoutToken(sipCallId: Int): Any = timeoutTokens.getOrPut(sipCallId) { Any() }

    companion object {
        private const val TAG = "IncomingCall"
        /** Longer than any sane PBX ring timeout; only catches calls that were never ended. */
        const val RING_TIMEOUT_MS = 90_000L
    }
}
