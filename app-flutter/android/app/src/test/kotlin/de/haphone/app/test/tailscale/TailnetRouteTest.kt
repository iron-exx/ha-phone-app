package de.haphone.app.test.tailscale

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TailnetRouteTest {
    @Test
    fun `running tunnel with a known PBX address uses the tailnet`() {
        assertTrue(TailnetRoute.useTailnet("100.101.102.103", tunnelRunning = true))
        assertEquals("100.101.102.103", TailnetRoute.sipHost("192.168.7.10", "100.101.102.103", true))
        assertEquals("100.101.102.103", TailnetRoute.apiHost("192.168.7.10:80", "100.101.102.103", true))
    }

    @Test
    fun `no tunnel or no PBX tailnet address falls back to the LAN`() {
        assertFalse(TailnetRoute.useTailnet("100.101.102.103", tunnelRunning = false))
        assertFalse(TailnetRoute.useTailnet(null, tunnelRunning = true))
        assertFalse(TailnetRoute.useTailnet("", tunnelRunning = true))
        assertEquals("192.168.7.10", TailnetRoute.sipHost("192.168.7.10", "100.101.102.103", false))
        assertEquals("192.168.7.10:80", TailnetRoute.apiHost("192.168.7.10:80", null, true))
    }
}
