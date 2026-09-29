package de.haphone.app.test.tailscale

import org.junit.Assert.assertEquals
import org.junit.Test

class LanProbeDecisionTest {
    private fun decide(current: Boolean, first: Boolean, followUps: List<Boolean>, networkChanged: Boolean = false): Pair<Boolean, Int> {
        var calls = 0
        val result = LanProbeDecision.decide(current, first, { followUps[calls++] }, 2, networkChanged)
        return result to calls
    }

    @Test
    fun sameResultNeedsNoConfirmation() {
        assertEquals(true to 0, decide(current = true, first = true, followUps = emptyList()))
    }

    @Test
    fun oneSlowProbeKeepsTheDirectRoute() {
        assertEquals(true to 1, decide(current = true, first = false, followUps = listOf(true, false)))
        assertEquals(true to 2, decide(current = true, first = false, followUps = listOf(false, true)))
    }

    @Test
    fun confirmedChangeFlips() {
        assertEquals(false to 2, decide(current = true, first = false, followUps = listOf(false, false)))
        assertEquals(true to 2, decide(current = false, first = true, followUps = listOf(true, true)))
    }

    @Test
    fun networkChangeDecidesAtOnce() {
        assertEquals(false to 0, decide(current = true, first = false, followUps = emptyList(), networkChanged = true))
    }
}
