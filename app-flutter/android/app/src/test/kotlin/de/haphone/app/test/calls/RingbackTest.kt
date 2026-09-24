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

class RingbackActionTest {
    @Test
    fun `only the call on screen starts or stops the ringback`() {
        org.junit.Assert.assertEquals(Ringback.Action.START, Ringback.actionFor(isCallOnScreen = true, isOutgoing = true, isEarly = true))
        org.junit.Assert.assertEquals(Ringback.Action.STOP, Ringback.actionFor(isCallOnScreen = true, isOutgoing = true, isEarly = false))
        org.junit.Assert.assertEquals(Ringback.Action.STOP, Ringback.actionFor(isCallOnScreen = true, isOutgoing = false, isEarly = true))
        // A held or waiting call changing state leaves the tone alone.
        org.junit.Assert.assertNull(Ringback.actionFor(isCallOnScreen = false, isOutgoing = false, isEarly = true))
        org.junit.Assert.assertNull(Ringback.actionFor(isCallOnScreen = false, isOutgoing = true, isEarly = false))
    }
}
