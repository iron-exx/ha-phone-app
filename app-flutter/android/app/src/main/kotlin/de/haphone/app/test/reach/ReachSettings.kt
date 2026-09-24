package de.haphone.app.test.reach

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * System settings pages the "Erreichbarkeit" screen can open. Pure mapping
 * ([actionFor]) plus the Android intent glue ([open]).
 */
object ReachSettings {
    /** Channel argument -> page. */
    enum class Target(val key: String) {
        EXACT_ALARM("exactAlarm"),
        BATTERY_OPTIMIZATION("batteryOptimization"),
        FULL_SCREEN_INTENT("fullScreenIntent"),
        NOTIFICATIONS("notifications"),
        APP_DETAILS("appDetails"),
        ;

        companion object {
            fun fromKey(key: String?): Target? = entries.firstOrNull { it.key == key }
        }
    }

    // Literal action strings (== the Settings constants) so the mapping is testable on any API level.
    const val ACTION_EXACT_ALARM = "android.settings.REQUEST_SCHEDULE_EXACT_ALARM"
    const val ACTION_REQUEST_IGNORE_BATTERY = "android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"
    const val ACTION_BATTERY_LIST = "android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS"
    const val ACTION_FULL_SCREEN_INTENT = "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT"
    const val ACTION_APP_NOTIFICATIONS = "android.settings.APP_NOTIFICATION_SETTINGS"
    const val ACTION_APP_DETAILS = "android.settings.APPLICATION_DETAILS_SETTINGS"

    /**
     * Settings action for [target]; pages that do not exist on [sdkInt] fall back to
     * the closest one. Battery: the one-tap request dialog while still optimized,
     * the full list once exempt (the dialog would do nothing then).
     */
    fun actionFor(target: Target, sdkInt: Int, ignoringBatteryOptimizations: Boolean): String = when (target) {
        Target.EXACT_ALARM -> if (sdkInt >= 31) ACTION_EXACT_ALARM else ACTION_APP_DETAILS
        Target.BATTERY_OPTIMIZATION ->
            if (ignoringBatteryOptimizations) ACTION_BATTERY_LIST else ACTION_REQUEST_IGNORE_BATTERY
        Target.FULL_SCREEN_INTENT -> if (sdkInt >= 34) ACTION_FULL_SCREEN_INTENT else ACTION_APP_NOTIFICATIONS
        Target.NOTIFICATIONS -> ACTION_APP_NOTIFICATIONS
        Target.APP_DETAILS -> ACTION_APP_DETAILS
    }

    /** Whether the page for [action] is addressed with a `package:` URI (vs. EXTRA_APP_PACKAGE or nothing). */
    fun usesPackageUri(action: String): Boolean = action in setOf(
        ACTION_EXACT_ALARM, ACTION_REQUEST_IGNORE_BATTERY, ACTION_FULL_SCREEN_INTENT, ACTION_APP_DETAILS,
    )

    /** Opens the page; falls back to the app details page. Returns false if nothing could be opened. */
    fun open(context: Context, target: Target): Boolean {
        val power = context.getSystemService(android.os.PowerManager::class.java)
        val exempt = power?.isIgnoringBatteryOptimizations(context.packageName) == true
        val action = actionFor(target, Build.VERSION.SDK_INT, exempt)
        if (start(context, intentFor(context, action))) return true
        return action != ACTION_APP_DETAILS && start(context, intentFor(context, ACTION_APP_DETAILS))
    }

    private fun intentFor(context: Context, action: String): Intent {
        val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (usesPackageUri(action)) intent.data = Uri.parse("package:${context.packageName}")
        if (action == ACTION_APP_NOTIFICATIONS) intent.putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        return intent
    }

    private fun start(context: Context, intent: Intent): Boolean = runCatching {
        context.startActivity(intent)
        true
    }.getOrElse {
        android.util.Log.w(ReachabilityMonitor.TAG, "settings page ${intent.action} not available", it)
        false
    }
}
