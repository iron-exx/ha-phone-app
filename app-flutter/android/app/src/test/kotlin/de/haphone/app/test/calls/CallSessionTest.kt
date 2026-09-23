package de.haphone.app.test.calls

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CallSessionTest {
    private fun call(number: String, state: String = "ringing") =
        CurrentCall("h$number", number, "", "incoming", video = false, doorCode = "", state = state)

    @Test
    fun `first incoming call is focused, second waits, third is rejected`() {
        val s = CallSession()
        assertEquals(CallSession.IncomingRole.FOCUSED, s.addIncoming(1, call("11")))
        assertEquals(CallSession.IncomingRole.WAITING, s.addIncoming(2, call("13")))
        assertEquals("waiting", s.other?.call?.state)
        assertEquals(CallSession.IncomingRole.REJECT, s.addIncoming(3, call("15")))
    }

    @Test
    fun `accepting the waiting call holds the current one`() {
        val s = CallSession()
        s.addIncoming(1, call("11", "confirmed"))
        s.addIncoming(2, call("13"))
        assertTrue(s.acceptWaiting())
        assertEquals(2, s.focused?.callId)
        assertEquals(1, s.other?.callId)
        assertTrue(s.other!!.call.onHold)
    }

    @Test
    fun `consultation call holds the first call and swap brings it back`() {
        val s = CallSession()
        s.addOutgoing(1, call("11", "confirmed"))
        assertTrue(s.addOutgoing(2, call("13", "connecting")))
        assertTrue(s.other!!.call.onHold)
        assertFalse(s.addOutgoing(3, call("15")))
        s.confirm(2, 1_000)
        assertTrue(s.swap())
        assertEquals(1, s.focused?.callId)
        assertFalse(s.focused!!.call.onHold)
        assertTrue(s.other!!.call.onHold)
    }

    @Test
    fun `a waiting call cannot be swapped to, only accepted`() {
        val s = CallSession()
        s.addIncoming(1, call("11", "confirmed"))
        s.addIncoming(2, call("13"))
        assertFalse(s.swap())
    }

    @Test
    fun `ending the focused call moves the other one up`() {
        val s = CallSession()
        s.addOutgoing(1, call("11", "confirmed"))
        s.addOutgoing(2, call("13", "confirmed"))
        assertEquals(2, s.remove(2)?.callId)
        assertEquals(1, s.focused?.callId)
        assertNull(s.other)
        assertEquals(1, s.remove(1)?.callId)
        assertTrue(s.isEmpty)
        assertNull(s.remove(1))
    }

    @Test
    fun `conference needs two answered calls and unholds both`() {
        val s = CallSession()
        s.addOutgoing(1, call("11", "confirmed"))
        s.addOutgoing(2, call("13", "connecting"))
        assertFalse(s.startConference())
        s.confirm(2, 5)
        assertTrue(s.startConference())
        assertTrue(s.conference)
        assertFalse(s.other!!.call.onHold)
        s.remove(2)
        assertFalse(s.conference)
    }

    @Test
    fun `pending outgoing id is bound once pjsua assigns one`() {
        val s = CallSession()
        s.addOutgoing(CallSession.PENDING_ID, call("11", "connecting"))
        s.bindPendingId(7)
        assertEquals(7, s.focused?.callId)
    }

    @Test
    fun `confirm keeps the first connect time`() {
        val s = CallSession()
        s.addIncoming(1, call("11"))
        s.confirm(1, 100)
        s.confirm(1, 900)
        assertEquals(100L, s.focused?.call?.connectedAtMs)
    }

    @Test
    fun `channel map carries the other call and the conference flag`() {
        val s = CallSession()
        assertNull(s.toChannelMap())
        s.addIncoming(1, call("11", "confirmed"))
        s.addIncoming(2, call("13"))
        val map = s.toChannelMap()!!
        assertEquals("11", map["number"])
        assertEquals("13", (map["other"] as Map<*, *>)["number"])
        assertEquals(false, map["conference"])
    }
}
