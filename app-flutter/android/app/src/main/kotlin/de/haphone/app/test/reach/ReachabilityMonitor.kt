package de.haphone.app.test.reach

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import de.haphone.app.test.HAPhoneTestApplication
import de.haphone.app.test.SipService
import de.haphone.app.test.reach.ReachPolicy.AlarmMode
import de.haphone.app.test.reach.ReachPolicy.WatchdogAction

/**
 * Keeps the SIP registration alive for days without a call, without push:
 *  - a Doze-proof alarm re-REGISTERs shortly before the binding expires,
 *  - a dropped TLS connection triggers an immediate re-REGISTER (then backoff),
 *  - a 15-minute WorkManager watchdog repairs a dead service or registration.
 * Each attempt holds a PARTIAL_WAKE_LOCK until PJSIP reports the result (or the
 * timeout), because in Doze the CPU would otherwise sleep before the 200 OK.
 *
 * Main thread only (PJSIP rule): PJSIP callbacks are posted here first.
 * Everything is logged with tag [TAG] so behaviour can be checked from logcat.
 */
object ReachabilityMonitor {
    const val TAG = "Reach"
    private const val PREFS = "haphone_reach"
    private const val WAKE_LOCK_TAG = "HAPhone:reach"
    /** An alarm stays armed while an attempt is in flight, in case its result never arrives. */
    private const val ATTEMPT_FALLBACK_SEC = 60L

    private var app: HAPhoneTestApplication? = null
    private var tracker = RegistrationTracker()
    private var wakeLock: PowerManager.WakeLock? = null

    fun attach(application: HAPhoneTestApplication) {
        if (app != null) return
        app = application
        tracker = RegistrationTracker(ReachClock.toElapsed(load(application), now(), wallNow()))
    }

    /** Monotonic clock for all expiry/due maths (see [ReachClock]); wall clock only for display. */
    private fun now() = android.os.SystemClock.elapsedRealtime()
    private fun wallNow() = System.currentTimeMillis()
    private fun wall(elapsedMs: Long?): Long? = ReachClock.toWall(elapsedMs, now(), wallNow())

    // ---- PJSIP events (already on main) ----

    fun onRegState(code: Int, expirationSec: Long, reason: String) {
        val a = app ?: return
        val mode = RegistrationAlarm.currentMode(a)
        val next = tracker.onResult(code, expirationSec, now(), mode)
        val result = ReachPolicy.classifyRegState(code, expirationSec)
        Log.i(TAG, "registration result code=$code reason=$reason expires=$expirationSec -> $result failures=${tracker.failures}")
        apply(a, next)
        save(a)
        releaseWakeLock("result $code")
    }

    fun onTransportState(type: String, state: Int, lastError: Int) {
        val a = app ?: return
        val name = transportStateName(state)
        if (state != org.pjsip.pjsua2.pjsip_transport_state.PJSIP_TP_STATE_DISCONNECTED) {
            Log.i(TAG, "transport $type state=$name")
            return
        }
        when (val reaction = tracker.onTransportDropped(now())) {
            DropReaction.Ignore -> Log.i(TAG, "transport $type dropped err=$lastError -> ignored (IP change or attempt in flight)")
            DropReaction.ReRegisterNow -> {
                Log.w(TAG, "transport $type dropped err=$lastError -> re-register now")
                reRegister("transport drop")
            }
            is DropReaction.RetryLater -> {
                Log.w(TAG, "transport $type dropped err=$lastError (drop #${tracker.drops}) -> retry in ${reaction.delaySec}s")
                arm(a, reaction.delaySec, "retry after drop")
            }
        }
        save(a)
    }

    /** Called right before PJSIP's own IP-change handling (it re-registers by itself). */
    fun onIpChange() {
        tracker.onIpChange(now())
        Log.i(TAG, "network changed; PJSIP handles re-registration")
    }

    // ---- Alarms (receiver, main thread) ----

    fun onRegisterAlarm(application: HAPhoneTestApplication) {
        attach(application)
        tracker.nextAlarmAtMs = null
        tracker.onWakeup(now())
        Log.i(TAG, "alarm fired kind=register mode=${RegistrationAlarm.currentMode(application)} registered=${tracker.isRegisteredAt(now())}")
        save(application)
        if (!application.hasValidCredentials()) {
            Log.i(TAG, "not provisioned, alarm ignored")
            return
        }
        // The alarm is a start-from-background exemption, so the service can come back here.
        if (!SipService.isRunning) application.startSipService()
        reRegister("alarm")
    }

    fun onRestartAlarm(application: HAPhoneTestApplication) {
        attach(application)
        tracker.onWakeup(now())
        Log.i(TAG, "alarm fired kind=restart service=${SipService.isRunning}")
        save(application)
        if (!application.hasValidCredentials()) return
        if (!SipService.isRunning) application.startSipService()
        if (!tracker.isRegisteredAt(now())) reRegister("restart")
    }

    fun onExactAlarmPermissionChanged(application: HAPhoneTestApplication) {
        attach(application)
        Log.i(TAG, "exact alarm permission changed: canScheduleExact=${RegistrationAlarm.canScheduleExact(application)}")
        rearm(application)
    }

    /** Service swiped away with the task: some OEMs kill the process right after. */
    fun onTaskRemoved(context: Context) {
        val mode = RegistrationAlarm.scheduleRestart(context, ReachPolicy.RESTART_DELAY_SEC.toLong())
        Log.i(TAG, "task removed; restart alarm in ${ReachPolicy.RESTART_DELAY_SEC}s ($mode)")
    }

    // ---- Watchdog (WorkManager, posted to main) ----

    fun runWatchdog(application: HAPhoneTestApplication) {
        attach(application)
        val provisioned = application.hasValidCredentials()
        val registered = tracker.isRegisteredAt(now())
        val actions = ReachPolicy.watchdogActions(provisioned, SipService.isRunning, registered)
        Log.i(TAG, "watchdog run provisioned=$provisioned service=${SipService.isRunning} registered=$registered actions=$actions")
        if (WatchdogAction.START_SERVICE in actions) application.startSipService()
        if (WatchdogAction.REREGISTER in actions) reRegister("watchdog")
        if (WatchdogAction.REARM_ALARM in actions) rearm(application)
    }

    // ---- Attempts ----

    fun reRegister(reason: String) {
        val a = app ?: return
        if (!a.hasValidCredentials()) {
            Log.i(TAG, "re-register ($reason) skipped: not provisioned")
            return
        }
        val now = now()
        if (!tracker.beginAttempt(now)) {
            Log.i(TAG, "re-register ($reason) skipped: attempt already in flight")
            return
        }
        acquireWakeLock(a)
        // Keep an alarm armed until the result replaces it with the real refresh/retry.
        arm(a, ATTEMPT_FALLBACK_SEC, "fallback while waiting for result")
        try {
            Log.i(TAG, "re-register reason=$reason")
            a.sipCallController.renewRegistration()
        } catch (e: Exception) {
            Log.w(TAG, "re-register ($reason) failed to send: ${e.message}")
            apply(a, tracker.attemptFailed(now()))
            save(a)
            releaseWakeLock("send failed")
        }
    }

    /** Re-arms the refresh alarm from the last result (watchdog, permission change). */
    private fun rearm(a: HAPhoneTestApplication) {
        val registeredAt = tracker.lastRegisteredAtMs
        val expiresAt = tracker.expiresAtMs
        if (!tracker.isRegisteredAt(now()) || registeredAt == null || expiresAt == null) {
            reRegister("rearm without registration")
            return
        }
        val granted = (expiresAt - registeredAt) / 1000
        val dueAt = registeredAt + ReachPolicy.refreshDelaySec(granted, RegistrationAlarm.currentMode(a)) * 1000
        val remainingSec = (dueAt - now()) / 1000
        if (remainingSec <= 0) reRegister("refresh overdue") else arm(a, remainingSec, "rearm")
    }

    private fun apply(a: HAPhoneTestApplication, next: NextAttempt) {
        when (next) {
            is NextAttempt.Refresh -> arm(a, next.delaySec, "refresh")
            is NextAttempt.Retry -> arm(a, next.delaySec, "retry #${tracker.failures}")
            NextAttempt.None -> {
                RegistrationAlarm.cancelAll(a)
                tracker.nextAlarmAtMs = null
                Log.i(TAG, "unregistered: alarms cancelled")
            }
        }
    }

    private fun arm(a: HAPhoneTestApplication, delaySec: Long, why: String) {
        val mode = RegistrationAlarm.scheduleRegister(a, delaySec)
        tracker.nextAlarmAtMs = now() + delaySec * 1000
        Log.i(TAG, "next alarm in ${delaySec}s ($why, ${if (mode == AlarmMode.EXACT_WHILE_IDLE) "exact" else "inexact"})")
    }

    /** Stop everything (credentials cleared / device unpaired). */
    fun stop(context: Context) {
        RegistrationAlarm.cancelAll(context)
        WatchdogWorker.cancel(context)
        tracker = RegistrationTracker()
        save(context)
        releaseWakeLock("stop")
        Log.i(TAG, "stopped: alarms and watchdog cancelled")
    }

    // ---- Wake lock ----

    private fun acquireWakeLock(context: Context) {
        val lock = wakeLock ?: context.getSystemService(PowerManager::class.java)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            ?.also { it.setReferenceCounted(false); wakeLock = it }
            ?: return
        lock.acquire(ReachPolicy.WAKE_LOCK_TIMEOUT_MS)
    }

    private fun releaseWakeLock(why: String) {
        val lock = wakeLock ?: return
        if (lock.isHeld) {
            runCatching { lock.release() }
            Log.i(TAG, "wake lock released ($why)")
        }
    }

    // ---- Snapshot for the Erreichbarkeit screen ----

    fun snapshot(context: Context): Map<String, Any?> {
        val power = context.getSystemService(PowerManager::class.java)
        val now = now()
        return mapOf(
            "notificationsEnabled" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
            "canUseFullScreenIntent" to canUseFullScreenIntent(context),
            "ignoringBatteryOptimizations" to (power?.isIgnoringBatteryOptimizations(context.packageName) == true),
            "canScheduleExactAlarms" to RegistrationAlarm.canScheduleExact(context),
            "registered" to tracker.isRegisteredAt(now),
            // Epoch ms for display; the tracker itself runs on elapsedRealtime.
            "lastRegisteredAt" to wall(tracker.lastRegisteredAtMs),
            "registrationExpiresAt" to wall(tracker.expiresAtMs),
            "lastWakeupAt" to wall(tracker.lastWakeupAtMs),
            "lastTransportDropAt" to wall(tracker.lastTransportDropAtMs),
            "nextAlarmAt" to wall(tracker.nextAlarmAtMs),
            "serviceRunning" to SipService.isRunning,
            "manufacturer" to Build.MANUFACTURER,
            "oemFamily" to ReachPolicy.oemFamily(Build.MANUFACTURER.orEmpty()),
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }

    private fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return context.getSystemService(NotificationManager::class.java)?.canUseFullScreenIntent() == true
    }

    private fun transportStateName(state: Int): String = when (state) {
        org.pjsip.pjsua2.pjsip_transport_state.PJSIP_TP_STATE_CONNECTED -> "CONNECTED"
        org.pjsip.pjsua2.pjsip_transport_state.PJSIP_TP_STATE_DISCONNECTED -> "DISCONNECTED"
        org.pjsip.pjsua2.pjsip_transport_state.PJSIP_TP_STATE_SHUTDOWN -> "SHUTDOWN"
        org.pjsip.pjsua2.pjsip_transport_state.PJSIP_TP_STATE_DESTROY -> "DESTROY"
        else -> "state$state"
    }

    // ---- Persistence (wall-clock timestamps, display only, not secret) ----

    private fun load(context: Context): PersistedReach {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        fun long(key: String): Long? = if (p.contains(key)) p.getLong(key, 0) else null
        return PersistedReach(long("lastRegisteredAt"), long("expiresAt"), long("lastWakeupAt"), long("lastTransportDropAt"))
    }

    private fun save(context: Context) {
        // Persisted as wall clock: elapsedRealtime restarts at 0 after a reboot.
        val s = ReachClock.toWall(tracker.persisted(), now(), wallNow())
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            fun put(key: String, v: Long?) { if (v == null) remove(key) else putLong(key, v) }
            put("lastRegisteredAt", s.lastRegisteredAtMs)
            put("expiresAt", s.expiresAtMs)
            put("lastWakeupAt", s.lastWakeupAtMs)
            put("lastTransportDropAt", s.lastTransportDropAtMs)
            apply()
        }
    }
}
