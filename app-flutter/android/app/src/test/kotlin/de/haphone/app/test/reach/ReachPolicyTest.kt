package de.haphone.app.test.reach

import de.haphone.app.test.reach.ReachPolicy.AlarmMode
import de.haphone.app.test.reach.ReachPolicy.RegResult
import de.haphone.app.test.reach.ReachPolicy.WatchdogAction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReachPolicyTest {
    @Test
    fun exactAlarmsAlwaysAllowedBelowApi31() {
        assertEquals(AlarmMode.EXACT_WHILE_IDLE, ReachPolicy.alarmMode(sdkInt = 30, canScheduleExactAlarms = false))
    }

    @Test
    fun api31PlusUsesExactOnlyWithPermission() {
        assertEquals(AlarmMode.EXACT_WHILE_IDLE, ReachPolicy.alarmMode(35, true))
        assertEquals(AlarmMode.INEXACT_WHILE_IDLE, ReachPolicy.alarmMode(35, false))
    }

    @Test
    fun exactRefreshIs120sBeforeExpiry() {
        assertEquals(480L, ReachPolicy.refreshDelaySec(600, AlarmMode.EXACT_WHILE_IDLE))
        assertEquals(3480L, ReachPolicy.refreshDelaySec(3600, AlarmMode.EXACT_WHILE_IDLE))
    }

    @Test
    fun shortGrantedExpiryRefreshesAtHalfButNotBelowMinimum() {
        assertEquals(60L, ReachPolicy.refreshDelaySec(120, AlarmMode.EXACT_WHILE_IDLE))
        assertEquals(ReachPolicy.MIN_REFRESH_DELAY_SEC.toLong(), ReachPolicy.refreshDelaySec(30, AlarmMode.EXACT_WHILE_IDLE))
    }

    @Test
    fun missingExpiryFallsBackToRequestedExpiry() {
        assertEquals(480L, ReachPolicy.refreshDelaySec(0, AlarmMode.EXACT_WHILE_IDLE))
    }

    @Test
    fun inexactRefreshStillLandsBeforeExpiryInWorstCaseWindow() {
        for (expires in listOf(120L, 300L, 600L, 3600L)) {
            val delay = ReachPolicy.refreshDelaySec(expires, AlarmMode.INEXACT_WHILE_IDLE)
            val latestDelivery = delay + delay * 3 / 4
            assertTrue("expires=$expires delay=$delay", latestDelivery <= expires - ReachPolicy.INEXACT_SAFETY_SEC || delay == ReachPolicy.MIN_REFRESH_DELAY_SEC.toLong())
        }
        assertEquals(308L, ReachPolicy.refreshDelaySec(600, AlarmMode.INEXACT_WHILE_IDLE))
    }

    @Test
    fun retryBackoffGrowsAndIsCapped() {
        assertEquals(listOf(5L, 15L, 30L, 60L, 120L, 300L, 300L, 300L), (1..8).map { ReachPolicy.retryDelaySec(it) })
        assertEquals(5L, ReachPolicy.retryDelaySec(0))
    }

    @Test
    fun regStateClassification() {
        assertEquals(RegResult.REGISTERED, ReachPolicy.classifyRegState(200, 600))
        assertEquals(RegResult.UNREGISTERED, ReachPolicy.classifyRegState(200, 0))
        assertEquals(RegResult.FAILED, ReachPolicy.classifyRegState(408, 0))
        assertEquals(RegResult.FAILED, ReachPolicy.classifyRegState(403, 600))
        with(ReachPolicy) {
            assertEquals("registered", RegResult.REGISTERED.channelName())
            assertEquals("unregistered", RegResult.UNREGISTERED.channelName())
            assertEquals("failed", RegResult.FAILED.channelName())
        }
    }

    @Test
    fun watchdogDoesNothingWhenNotProvisioned() {
        assertEquals(emptySet<WatchdogAction>(), ReachPolicy.watchdogActions(provisioned = false, serviceRunning = false, registered = false))
    }

    @Test
    fun watchdogHealthyOnlyRearmsAlarm() {
        assertEquals(setOf(WatchdogAction.REARM_ALARM), ReachPolicy.watchdogActions(true, serviceRunning = true, registered = true))
    }

    @Test
    fun watchdogRepairsServiceAndRegistration() {
        assertEquals(
            setOf(WatchdogAction.START_SERVICE, WatchdogAction.REREGISTER),
            ReachPolicy.watchdogActions(true, serviceRunning = false, registered = false),
        )
        assertEquals(setOf(WatchdogAction.REREGISTER), ReachPolicy.watchdogActions(true, serviceRunning = true, registered = false))
        assertEquals(
            setOf(WatchdogAction.START_SERVICE, WatchdogAction.REARM_ALARM),
            ReachPolicy.watchdogActions(true, serviceRunning = false, registered = true),
        )
    }

    @Test
    fun oemFamilies() {
        assertEquals("samsung", ReachPolicy.oemFamily("samsung"))
        assertEquals("xiaomi", ReachPolicy.oemFamily("Xiaomi"))
        assertEquals("xiaomi", ReachPolicy.oemFamily("Redmi"))
        assertEquals("huawei", ReachPolicy.oemFamily("HUAWEI"))
        assertEquals("huawei", ReachPolicy.oemFamily("HONOR"))
        assertEquals("oneplus", ReachPolicy.oemFamily("OnePlus"))
        assertEquals("oppo", ReachPolicy.oemFamily("realme"))
        assertEquals("google", ReachPolicy.oemFamily("Google"))
        assertEquals("other", ReachPolicy.oemFamily(" Fairphone "))
        assertEquals("other", ReachPolicy.oemFamily(""))
    }
}
