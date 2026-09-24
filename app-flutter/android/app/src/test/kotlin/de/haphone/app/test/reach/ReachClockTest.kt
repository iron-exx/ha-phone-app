package de.haphone.app.test.reach

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReachClockTest {
    private val nowElapsed = 50_000L
    private val nowWall = 1_700_000_000_000L

    @Test
    fun `elapsed instants convert to wall clock for display`() {
        assertEquals(nowWall - 10_000L, ReachClock.toWall(40_000L, nowElapsed, nowWall))
        assertEquals(nowWall + 120_000L, ReachClock.toWall(170_000L, nowElapsed, nowWall))
        assertNull(ReachClock.toWall(null as Long?, nowElapsed, nowWall))
    }

    @Test
    fun `persisted wall times round-trip through the elapsed axis`() {
        val persisted = PersistedReach(nowWall - 5_000L, nowWall + 600_000L, null, nowWall - 90_000_000L)
        val elapsed = ReachClock.toElapsed(persisted, nowElapsed, nowWall)
        assertEquals(45_000L, elapsed.lastRegisteredAtMs)
        assertEquals(650_000L, elapsed.expiresAtMs)
        assertNull(elapsed.lastWakeupAtMs)
        // Before this boot: negative on the elapsed axis, still displays correctly.
        assertEquals(nowElapsed - 90_000_000L, elapsed.lastTransportDropAtMs)
        assertEquals(persisted, ReachClock.toWall(elapsed, nowElapsed, nowWall))
    }

    @Test
    fun `a wall clock jump does not move an elapsed expiry`() {
        val tracker = RegistrationTracker()
        tracker.onResult(200, 600, nowElapsed, ReachPolicy.AlarmMode.EXACT_WHILE_IDLE)
        // The user sets the clock back a day: only the display changes, not the expiry maths.
        val later = nowElapsed + 599_000L
        assertEquals(true, tracker.isRegisteredAt(later))
        val shownBefore = ReachClock.toWall(tracker.expiresAtMs, later, nowWall + 599_000L)
        val shownAfterJump = ReachClock.toWall(tracker.expiresAtMs, later, nowWall + 599_000L - 86_400_000L)
        assertEquals(86_400_000L, shownBefore!! - shownAfterJump!!)
        assertEquals(true, tracker.isRegisteredAt(later))
    }
}
