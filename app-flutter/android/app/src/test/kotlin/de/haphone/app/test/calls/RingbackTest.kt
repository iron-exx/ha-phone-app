package de.haphone.app.test.calls

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RingbackTest {
    @Test
    fun `plays only while an outgoing call is ringing`() {
        assertTrue(Ringback.shouldPlay(isOutgoing = true, isEarly = true))
        assertFalse(Ringback.shouldPlay(isOutgoing = true, isEarly = false))
        assertFalse(Ringback.shouldPlay(isOutgoing = false, isEarly = true))
    }
}
