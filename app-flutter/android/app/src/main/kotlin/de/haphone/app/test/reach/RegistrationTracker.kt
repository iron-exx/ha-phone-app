package de.haphone.app.test.reach

import de.haphone.app.test.reach.ReachPolicy.AlarmMode
import de.haphone.app.test.reach.ReachPolicy.RegResult

/** What to schedule after a registration result. */
sealed interface NextAttempt {
    /** Registered: refresh before the binding expires. */
    data class Refresh(val delaySec: Long) : NextAttempt
    /** Failed: try again with backoff. */
    data class Retry(val delaySec: Long) : NextAttempt
    /** Deliberately unregistered: nothing to schedule. */
    data object None : NextAttempt
}

/** Reaction to a dropped SIP transport (TLS connection). */
sealed interface DropReaction {
    /** PJSIP is already handling it (IP change, attempt in flight). */
    data object Ignore : DropReaction
    /** First drop since the last good registration: re-REGISTER right away. */
    data object ReRegisterNow : DropReaction
    /** Flapping connection: back off. */
    data class RetryLater(val delaySec: Long) : DropReaction
}

/** Timestamps kept across process restarts (display only; registered never survives a restart). */
data class PersistedReach(
    val lastRegisteredAtMs: Long? = null,
    val expiresAtMs: Long? = null,
    val lastWakeupAtMs: Long? = null,
    val lastTransportDropAtMs: Long? = null,
)

/**
 * Registration bookkeeping for the reachability layer. Pure: every method gets the
 * current time, nothing touches Android or PJSIP. Main thread only (no locking).
 */
class RegistrationTracker(restored: PersistedReach = PersistedReach()) {
    var registered = false
        private set
    var lastRegisteredAtMs: Long? = restored.lastRegisteredAtMs
        private set
    var expiresAtMs: Long? = restored.expiresAtMs
        private set
    var lastWakeupAtMs: Long? = restored.lastWakeupAtMs
        private set
    var lastTransportDropAtMs: Long? = restored.lastTransportDropAtMs
        private set
    var lastResultCode: Int? = null
        private set
    var failures = 0
        private set
    var drops = 0
        private set
    /** When the pending alarm fires (set by the scheduler), null if none. */
    var nextAlarmAtMs: Long? = null

    private var attemptStartedAtMs: Long? = null
    private var ipChangeAtMs: Long? = null

    fun persisted() = PersistedReach(lastRegisteredAtMs, expiresAtMs, lastWakeupAtMs, lastTransportDropAtMs)

    fun isRegisteredAt(nowMs: Long): Boolean = registered && (expiresAtMs ?: 0L) > nowMs

    fun attemptInFlight(nowMs: Long): Boolean {
        val started = attemptStartedAtMs ?: return false
        return nowMs - started < ReachPolicy.ATTEMPT_STALE_MS
    }

    /** Returns false if another attempt is still waiting for its result. */
    fun beginAttempt(nowMs: Long): Boolean {
        if (attemptInFlight(nowMs)) return false
        attemptStartedAtMs = nowMs
        return true
    }

    /** The attempt could not even be sent (e.g. PJSIP threw); counts as a failure. */
    fun attemptFailed(nowMs: Long): NextAttempt = onResult(code = 0, expirationSec = 0, nowMs = nowMs, mode = AlarmMode.EXACT_WHILE_IDLE)

    fun onWakeup(nowMs: Long) {
        lastWakeupAtMs = nowMs
    }

    fun onIpChange(nowMs: Long) {
        ipChangeAtMs = nowMs
    }

    fun onResult(code: Int, expirationSec: Long, nowMs: Long, mode: AlarmMode): NextAttempt {
        attemptStartedAtMs = null
        lastResultCode = code
        return when (ReachPolicy.classifyRegState(code, expirationSec)) {
            RegResult.REGISTERED -> {
                registered = true
                lastRegisteredAtMs = nowMs
                expiresAtMs = nowMs + expirationSec * 1000
                failures = 0
                drops = 0
                NextAttempt.Refresh(ReachPolicy.refreshDelaySec(expirationSec, mode))
            }
            RegResult.UNREGISTERED -> {
                registered = false
                expiresAtMs = null
                failures = 0
                NextAttempt.None
            }
            RegResult.FAILED -> {
                registered = false
                failures++
                NextAttempt.Retry(ReachPolicy.retryDelaySec(failures))
            }
        }
    }

    fun onTransportDropped(nowMs: Long): DropReaction {
        lastTransportDropAtMs = nowMs
        // Whatever the cause, the PBX can no longer reach us over that connection.
        registered = false
        val sinceIpChange = ipChangeAtMs?.let { nowMs - it }
        if (sinceIpChange != null && sinceIpChange in 0 until ReachPolicy.IP_CHANGE_QUIET_MS) return DropReaction.Ignore
        if (attemptInFlight(nowMs)) return DropReaction.Ignore
        drops++
        return if (drops == 1) DropReaction.ReRegisterNow else DropReaction.RetryLater(ReachPolicy.retryDelaySec(drops - 1))
    }
}
