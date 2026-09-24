package de.haphone.app.test.reach

import de.haphone.app.test.reach.ReachSettings.Target
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReachSettingsTest {
    @Test
    fun channelKeysMapToTargets() {
        assertEquals(Target.EXACT_ALARM, Target.fromKey("exactAlarm"))
        assertEquals(Target.BATTERY_OPTIMIZATION, Target.fromKey("batteryOptimization"))
        assertEquals(Target.FULL_SCREEN_INTENT, Target.fromKey("fullScreenIntent"))
        assertEquals(Target.NOTIFICATIONS, Target.fromKey("notifications"))
        assertEquals(Target.APP_DETAILS, Target.fromKey("appDetails"))
        assertNull(Target.fromKey("autostart"))
        assertNull(Target.fromKey(null))
    }

    @Test
    fun exactAlarmPageOnlyFromApi31() {
        assertEquals(ReachSettings.ACTION_EXACT_ALARM, ReachSettings.actionFor(Target.EXACT_ALARM, 31, false))
        assertEquals(ReachSettings.ACTION_APP_DETAILS, ReachSettings.actionFor(Target.EXACT_ALARM, 30, false))
    }

    @Test
    fun batteryUsesRequestDialogUntilExempt() {
        assertEquals(ReachSettings.ACTION_REQUEST_IGNORE_BATTERY, ReachSettings.actionFor(Target.BATTERY_OPTIMIZATION, 35, false))
        assertEquals(ReachSettings.ACTION_BATTERY_LIST, ReachSettings.actionFor(Target.BATTERY_OPTIMIZATION, 35, true))
    }

    @Test
    fun fullScreenIntentPageOnlyFromApi34() {
        assertEquals(ReachSettings.ACTION_FULL_SCREEN_INTENT, ReachSettings.actionFor(Target.FULL_SCREEN_INTENT, 34, true))
        assertEquals(ReachSettings.ACTION_APP_NOTIFICATIONS, ReachSettings.actionFor(Target.FULL_SCREEN_INTENT, 33, true))
    }

    @Test
    fun actionStringsMatchPlatformConstants() {
        assertEquals(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, ReachSettings.ACTION_EXACT_ALARM)
        assertEquals(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, ReachSettings.ACTION_REQUEST_IGNORE_BATTERY)
        assertEquals(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS, ReachSettings.ACTION_BATTERY_LIST)
        assertEquals(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, ReachSettings.ACTION_FULL_SCREEN_INTENT)
        assertEquals(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS, ReachSettings.ACTION_APP_NOTIFICATIONS)
        assertEquals(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, ReachSettings.ACTION_APP_DETAILS)
    }

    @Test
    fun packageUriOnlyForPerAppPages() {
        assertTrue(ReachSettings.usesPackageUri(ReachSettings.ACTION_EXACT_ALARM))
        assertTrue(ReachSettings.usesPackageUri(ReachSettings.ACTION_APP_DETAILS))
        assertFalse(ReachSettings.usesPackageUri(ReachSettings.ACTION_BATTERY_LIST))
        assertFalse(ReachSettings.usesPackageUri(ReachSettings.ACTION_APP_NOTIFICATIONS))
    }
}
