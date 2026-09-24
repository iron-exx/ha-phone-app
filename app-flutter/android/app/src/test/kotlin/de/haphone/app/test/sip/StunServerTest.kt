package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StunServerTest {
    @Test
    fun `replaces the SIP port with the STUN port`() {
        assertEquals("192.168.7.10:3478", StunServer.forDomain("192.168.7.10:5061"))
        assertEquals("pbx.local:3478", StunServer.forDomain("pbx.local"))
    }

    @Test
    fun `keeps IPv6 hosts bracketed`() {
        assertEquals("[fd00::1]:3478", StunServer.forDomain("[fd00::1]:5061"))
        assertEquals("[fd00::1]:3478", StunServer.forDomain("fd00::1"))
    }

    @Test
    fun `empty domain gives no server`() {
        assertNull(StunServer.forDomain(""))
        assertNull(StunServer.forDomain("  "))
    }
}
