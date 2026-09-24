package de.haphone.app.test.reach

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import de.haphone.app.test.reach.ReachPolicy.AlarmMode

/**
 * Doze-proof alarms for the SIP registration. Two independent alarms:
 *  - [ACTION_REGISTER]: refresh before expiry, or retry after a failure (one
 *    PendingIntent, every schedule replaces the previous one).
 *  - [ACTION_RESTART]: brings the foreground service back after the task was swiped away.
 * Both use the ELAPSED_REALTIME_WAKEUP clock, which keeps counting in deep sleep.
 */
object RegistrationAlarm {
    const val ACTION_REGISTER = "de.haphone.app.test.reach.REGISTER"
    const val ACTION_RESTART = "de.haphone.app.test.reach.RESTART"
    private const val REQUEST_REGISTER = 7101
    private const val REQUEST_RESTART = 7102

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
    }

    fun currentMode(context: Context): AlarmMode = ReachPolicy.alarmMode(Build.VERSION.SDK_INT, canScheduleExact(context))

    /** Returns the mode actually used (exact may degrade to inexact if the permission was just revoked). */
    fun scheduleRegister(context: Context, delaySec: Long): AlarmMode = schedule(context, ACTION_REGISTER, REQUEST_REGISTER, delaySec)

    fun scheduleRestart(context: Context, delaySec: Long): AlarmMode = schedule(context, ACTION_RESTART, REQUEST_RESTART, delaySec)

    fun cancelAll(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        alarms.cancel(pendingIntent(context, ACTION_REGISTER, REQUEST_REGISTER))
        alarms.cancel(pendingIntent(context, ACTION_RESTART, REQUEST_RESTART))
    }

    private fun schedule(context: Context, action: String, request: Int, delaySec: Long): AlarmMode {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return AlarmMode.INEXACT_WHILE_IDLE
        val at = SystemClock.elapsedRealtime() + delaySec * 1000
        val pi = pendingIntent(context, action, request)
        val mode = currentMode(context)
        if (mode == AlarmMode.EXACT_WHILE_IDLE) {
            // canScheduleExactAlarms() can flip between the check and the call.
            val ok = runCatching { alarms.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi) }
                .onFailure { Log.w(ReachabilityMonitor.TAG, "exact alarm refused, falling back to inexact", it) }
                .isSuccess
            if (ok) return AlarmMode.EXACT_WHILE_IDLE
        }
        alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
        return AlarmMode.INEXACT_WHILE_IDLE
    }

    private fun pendingIntent(context: Context, action: String, request: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            request,
            Intent(context, RegistrationAlarmReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

/**
 * Alarm target. AlarmManager holds a wake lock only for the duration of onReceive;
 * [ReachabilityMonitor] takes its own before returning. Also re-arms when the user
 * grants "Alarme & Erinnerungen" (exact alarms) so the better mode is used at once.
 */
class RegistrationAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext as? de.haphone.app.test.HAPhoneTestApplication ?: return
        // onReceive runs on the main thread, where PJSIP must be driven from.
        runCatching {
            when (intent.action) {
                RegistrationAlarm.ACTION_REGISTER -> ReachabilityMonitor.onRegisterAlarm(app)
                RegistrationAlarm.ACTION_RESTART -> ReachabilityMonitor.onRestartAlarm(app)
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> ReachabilityMonitor.onExactAlarmPermissionChanged(app)
            }
        }.onFailure { Log.e(ReachabilityMonitor.TAG, "alarm ${intent.action} failed", it) }
    }
}
