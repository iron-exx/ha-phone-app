package de.haphone.app.test.reach

import de.haphone.app.test.reach.ReachPolicy.AlarmMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RegistrationTrackerTest {
    private val t0 = 1_000_000L
    private val exact = AlarmMode.EXACT_WHILE_IDLE

    @Test
    fun successfulRegistrationSchedulesRefreshAndRecordsTimes() {
        val tracker = RegistrationTracker()
        assertTrue(tracker.beginAttempt(t0))
        val next = tracker.onResult(200, 600, t0 + 300, exact)

        assertEquals(NextAttempt.Refresh(480), next)
        assertTrue(tracker.isRegisteredAt(t0 + 300))
        assertEquals(t0 + 300, tracker.lastRegisteredAtMs)
        assertEquals(t0 + 300 + 600_000, tracker.expiresAtMs)
        assertFalse(tracker.attemptInFlight(t0 + 400))
    }

    @Test
    fun registrationCountsAsGoneAfterExpiry() {
        val tracker = RegistrationTracker()
        tracker.onResult(200, 600, t0, exact)
        assertTrue(tracker.isRegisteredAt(t0 + 599_999))
        assertFalse(tracker.isRegisteredAt(t0 + 600_000))
    }

    @Test
    fun failuresBackOffAndSuccessResets() {
        val tracker = RegistrationTracker()
        assertEquals(NextAttempt.Retry(5), tracker.onResult(408, 0, t0, exact))
        assertEquals(NextAttempt.Retry(15), tracker.onResult(503, 0, t0, exact))
        assertEquals(NextAttempt.Retry(30), tracker.attemptFailed(t0))
        assertEquals(3, tracker.failures)
        assertFalse(tracker.registered)

        tracker.onResult(200, 600, t0, exact)
        assertEquals(0, tracker.failures)
        assertEquals(NextAttempt.Retry(5), tracker.onResult(408, 0, t0, exact))
    }

    @Test
    fun unregisterSchedulesNothing() {
        val tracker = RegistrationTracker()
        tracker.onResult(200, 600, t0, exact)
        assertEquals(NextAttempt.None, tracker.onResult(200, 0, t0 + 1, exact))
        assertFalse(tracker.isRegisteredAt(t0 + 2))
        assertNull(tracker.expiresAtMs)
    }

    @Test
    fun onlyOneAttemptInFlightUntilResultOrStale() {
        val tracker = RegistrationTracker()
        assertTrue(tracker.beginAttempt(t0))
        assertFalse(tracker.beginAttempt(t0 + 1_000))
        assertTrue(tracker.beginAttempt(t0 + ReachPolicy.ATTEMPT_STALE_MS))
        tracker.onResult(200, 600, t0, exact)
        assertTrue(tracker.beginAttempt(t0 + ReachPolicy.ATTEMPT_STALE_MS + 1))
    }

    @Test
    fun firstTransportDropReRegistersNowThenBacksOff() {
        val tracker = RegistrationTracker()
        tracker.onResult(200, 600, t0, exact)

        assertEquals(DropReaction.ReRegisterNow, tracker.onTransportDropped(t0 + 100_000))
        assertFalse(tracker.isRegisteredAt(t0 + 100_000))
        assertEquals(t0 + 100_000, tracker.lastTransportDropAtMs)
        assertEquals(DropReaction.RetryLater(5), tracker.onTransportDropped(t0 + 200_000))
        assertEquals(DropReaction.RetryLater(15), tracker.onTransportDropped(t0 + 300_000))

        tracker.onResult(200, 600, t0 + 400_000, exact)
        assertEquals(DropReaction.ReRegisterNow, tracker.onTransportDropped(t0 + 500_000))
    }

    @Test
    fun dropRightAfterIpChangeIsLeftToPjsip() {
        val tracker = RegistrationTracker()
        tracker.onIpChange(t0)
        assertEquals(DropReaction.Ignore, tracker.onTransportDropped(t0 + 2_000))
        assertEquals(0, tracker.drops)
        assertEquals(DropReaction.ReRegisterNow, tracker.onTransportDropped(t0 + ReachPolicy.IP_CHANGE_QUIET_MS))
    }

    @Test
    fun dropDuringOwnAttemptIsIgnored() {
        val tracker = RegistrationTracker()
        tracker.beginAttempt(t0)
        assertEquals(DropReaction.Ignore, tracker.onTransportDropped(t0 + 1_000))
    }

    @Test
    fun timestampsSurviveRestartButRegisteredDoesNot() {
        val tracker = RegistrationTracker()
        tracker.onResult(200, 600, t0, exact)
        tracker.onWakeup(t0 + 5)
        tracker.onTransportDropped(t0 + 7)
        tracker.onResult(200, 600, t0 + 9, exact)

        val restored = RegistrationTracker(tracker.persisted())
        assertEquals(PersistedReach(t0 + 9, t0 + 9 + 600_000, t0 + 5, t0 + 7), restored.persisted())
        assertFalse(restored.isRegisteredAt(t0 + 10))
    }
}
