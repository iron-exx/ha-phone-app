package de.haphone.app.test.reach

/**
 * Pure timing and decision rules that keep the SIP registration alive for days
 * without a call (no push). No Android types here, so everything is JVM-testable;
 * the platform glue lives in [ReachabilityMonitor], [RegistrationAlarm] and
 * [WatchdogWorker].
 *
 * Why an app-side alarm at all: in Doze the CPU sleeps and PJSIP's own refresh
 * timer (expires - 5 s) does not run, so the registration can silently expire at
 * the PBX. An AlarmManager "allow while idle" alarm does fire in Doze.
 */
object ReachPolicy {
    /** Registration expiry we ask the PBX for (Asterisk accepts 60..7200 s by default). */
    const val REGISTRATION_EXPIRES_SEC = 600

    /** Exact alarm: re-REGISTER this long before the binding expires. */
    const val REFRESH_LEAD_SEC = 120

    /** Never refresh more often than this, even if the PBX grants a tiny expiry. */
    const val MIN_REFRESH_DELAY_SEC = 30

    /** Safety margin the inexact alarm's worst-case delivery must still keep before expiry. */
    const val INEXACT_SAFETY_SEC = 60

    /**
     * AlarmManager lets an inexact alarm (API 19+ window heuristic) fire up to
     * 0.75 x its delay late; the worst case is delay * 7/4.
     */
    private const val INEXACT_WINDOW_NUM = 7
    private const val INEXACT_WINDOW_DEN = 4

    /** Retry schedule after a failed registration or a dropped TLS connection. */
    val RETRY_BACKOFF_SEC = listOf(5, 15, 30, 60, 120, 300)

    /** A wake lock held for a re-REGISTER is released after this at the latest. */
    const val WAKE_LOCK_TIMEOUT_MS = 20_000L

    /** An attempt without a result after this long no longer blocks new attempts. */
    const val ATTEMPT_STALE_MS = 30_000L

    /** PJSIP re-registers by itself after an IP change; transport drops right after are ours to ignore. */
    const val IP_CHANGE_QUIET_MS = 10_000L

    /** WorkManager's minimum periodic interval. */
    const val WATCHDOG_INTERVAL_MIN = 15L

    /** Delay before the alarm that brings the service back after the task was swiped away. */
    const val RESTART_DELAY_SEC = 5

    enum class AlarmMode { EXACT_WHILE_IDLE, INEXACT_WHILE_IDLE }

    /** Exact alarms need SCHEDULE_EXACT_ALARM from API 31 (user-grantable); below that they are always allowed. */
    fun alarmMode(sdkInt: Int, canScheduleExactAlarms: Boolean): AlarmMode =
        if (sdkInt < 31 || canScheduleExactAlarms) AlarmMode.EXACT_WHILE_IDLE else AlarmMode.INEXACT_WHILE_IDLE

    /**
     * Seconds after a successful registration until the refresh alarm.
     * Exact: `expires - min(120, expires/2)`. Inexact: early enough that even the
     * latest allowed delivery (delay * 7/4) still lands [INEXACT_SAFETY_SEC] before expiry.
     */
    fun refreshDelaySec(grantedExpiresSec: Long, mode: AlarmMode): Long {
        val expires = if (grantedExpiresSec > 0) grantedExpiresSec else REGISTRATION_EXPIRES_SEC.toLong()
        val delay = when (mode) {
            AlarmMode.EXACT_WHILE_IDLE -> expires - minOf(REFRESH_LEAD_SEC.toLong(), expires / 2)
            AlarmMode.INEXACT_WHILE_IDLE ->
                (expires - INEXACT_SAFETY_SEC) * INEXACT_WINDOW_DEN / INEXACT_WINDOW_NUM
        }
        return maxOf(MIN_REFRESH_DELAY_SEC.toLong(), delay)
    }

    /** [failures] = consecutive failures so far (1 = first failure). */
    fun retryDelaySec(failures: Int): Long {
        val index = (failures - 1).coerceIn(0, RETRY_BACKOFF_SEC.lastIndex)
        return RETRY_BACKOFF_SEC[index].toLong()
    }

    enum class RegResult { REGISTERED, UNREGISTERED, FAILED }

    /** Same rule HAPhoneAccount.onRegState always used: 2xx with expiry = registered, 2xx without = unregistered. */
    fun classifyRegState(code: Int, expirationSec: Long): RegResult = when {
        code / 100 == 2 && expirationSec > 0 -> RegResult.REGISTERED
        code / 100 == 2 -> RegResult.UNREGISTERED
        else -> RegResult.FAILED
    }

    fun RegResult.channelName(): String = when (this) {
        RegResult.REGISTERED -> "registered"
        RegResult.UNREGISTERED -> "unregistered"
        RegResult.FAILED -> "failed"
    }

    enum class WatchdogAction { START_SERVICE, REREGISTER, REARM_ALARM }

    /** What the 15-minute watchdog has to repair. Nothing at all while not provisioned. */
    fun watchdogActions(provisioned: Boolean, serviceRunning: Boolean, registered: Boolean): Set<WatchdogAction> {
        if (!provisioned) return emptySet()
        val actions = linkedSetOf<WatchdogAction>()
        if (!serviceRunning) actions += WatchdogAction.START_SERVICE
        actions += if (registered) WatchdogAction.REARM_ALARM else WatchdogAction.REREGISTER
        return actions
    }

    /** OEM family for vendor-specific "keep the app alive" advice in the Erreichbarkeit screen. */
    fun oemFamily(manufacturer: String): String {
        val m = manufacturer.trim().lowercase()
        return when {
            m.contains("samsung") -> "samsung"
            m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") -> "xiaomi"
            m.contains("huawei") || m.contains("honor") -> "huawei"
            m.contains("oneplus") -> "oneplus"
            m.contains("oppo") || m.contains("realme") -> "oppo"
            m.contains("vivo") -> "vivo"
            m.contains("google") -> "google"
            else -> "other"
        }
    }
}
