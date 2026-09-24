package de.haphone.app.test.ring

import de.haphone.app.test.ring.RingPolicy.Companion.rejects
import de.haphone.app.test.ring.RingPolicy.Decision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RingPolicyTest {
    private val now = 1_700_000_000_000L

    @Test
    fun defaultRingsForEveryone() {
        val p = RingPolicy()
        assertTrue(p.enabled)
        assertTrue(p.allowDoor)
        assertEquals(Decision.RING, p.decide(now, isDoor = false))
        assertEquals(Decision.RING, p.decide(now, isDoor = true))
    }

    @Test
    fun disabledRejectsNormalCalls() {
        val p = RingPolicy(enabled = false)
        assertEquals(Decision.REJECT_DISABLED, p.decide(now, isDoor = false))
        assertTrue(p.decide(now, false).rejects())
    }

    @Test
    fun disabledStillRingsForDoorWhenAllowed() {
        assertEquals(Decision.RING_DOOR_OVERRIDE, RingPolicy(enabled = false).decide(now, isDoor = true))
        assertFalse(Decision.RING_DOOR_OVERRIDE.rejects())
    }

    @Test
    fun disabledRejectsDoorWhenDoorOverrideOff() {
        assertEquals(Decision.REJECT_DISABLED, RingPolicy(enabled = false, allowDoor = false).decide(now, isDoor = true))
    }

    @Test
    fun mutedUntilFutureRejects() {
        val p = RingPolicy(mutedUntilMs = now + 60_000)
        assertTrue(p.isMutedAt(now))
        assertFalse(p.ringsAt(now))
        assertEquals(Decision.REJECT_MUTED, p.decide(now, isDoor = false))
        assertEquals(Decision.RING_DOOR_OVERRIDE, p.decide(now, isDoor = true))
    }

    @Test
    fun mutedUntilPastRingsAgain() {
        val p = RingPolicy(mutedUntilMs = now - 1)
        assertFalse(p.isMutedAt(now))
        assertEquals(Decision.RING, p.decide(now, isDoor = false))
    }

    @Test
    fun muteEndsExactlyAtTheGivenTime() {
        assertEquals(Decision.RING, RingPolicy(mutedUntilMs = now).decide(now, isDoor = false))
    }

    @Test
    fun normalizedDropsExpiredMuteOnly() {
        assertEquals(0L, RingPolicy(mutedUntilMs = now - 5).normalized(now).mutedUntilMs)
        assertEquals(now + 5, RingPolicy(mutedUntilMs = now + 5).normalized(now).mutedUntilMs)
    }

    @Test
    fun mapRoundTrip() {
        val p = RingPolicy(enabled = false, mutedUntilMs = now, allowDoor = false)
        assertEquals(p, RingPolicy.fromMap(p.toMap()))
    }

    @Test
    fun fromMapKeepsBaseForMissingKeysAndAcceptsInts() {
        val base = RingPolicy(enabled = false, mutedUntilMs = 5, allowDoor = false)
        assertEquals(base.copy(allowDoor = true), RingPolicy.fromMap(mapOf("allowDoor" to true), base))
        assertEquals(42L, RingPolicy.fromMap(mapOf("mutedUntil" to 42)).mutedUntilMs)
        assertEquals(0L, RingPolicy.fromMap(mapOf("mutedUntil" to -3)).mutedUntilMs)
    }

    @Test
    fun doorDetection() {
        val doors = setOf("16", "17")
        assertTrue(RingPolicy.isDoor("16", doors::contains, hasVideo = false))
        assertFalse(RingPolicy.isDoor("11", doors::contains, hasVideo = false))
        assertTrue(RingPolicy.isDoor("11", doors::contains, hasVideo = true))
        assertFalse(RingPolicy.isDoor("", { true }, hasVideo = false))
    }

    @Test
    fun rejectStatusIs480() {
        assertEquals(480, RingPolicy.REJECT_STATUS)
    }
}
