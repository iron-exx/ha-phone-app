package de.haphone.app.test.tailscale

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TailnetRoutesTest {

    @Test
    fun `the tailnet ranges themselves and hosts inside them pass`() {
        assertTrue(TailnetRoutes.isAllowed("100.64.0.0", 10))
        assertTrue(TailnetRoutes.isAllowed("100.101.102.103", 32))
        assertTrue(TailnetRoutes.isAllowed("100.127.255.255", 32))
        assertTrue(TailnetRoutes.isAllowed("fd7a:115c:a1e0::", 48))
        assertTrue(TailnetRoutes.isAllowed("fd7a:115c:a1e0:ab12::1", 128))
    }

    @Test
    fun `default routes, exit-node halves and subnet routes are dropped`() {
        assertFalse(TailnetRoutes.isAllowed("0.0.0.0", 0))
        assertFalse(TailnetRoutes.isAllowed("0.0.0.0", 1))
        assertFalse(TailnetRoutes.isAllowed("128.0.0.0", 1))
        assertFalse(TailnetRoutes.isAllowed("::", 0))
        assertFalse(TailnetRoutes.isAllowed("192.168.7.0", 24))
        assertFalse(TailnetRoutes.isAllowed("2000::", 3))
    }

    @Test
    fun `wider or neighbouring prefixes of the tailnet range are dropped`() {
        // 100.0.0.0/8 contains the CGNAT range but also normal internet addresses.
        assertFalse(TailnetRoutes.isAllowed("100.0.0.0", 8))
        assertFalse(TailnetRoutes.isAllowed("100.63.255.255", 32))
        assertFalse(TailnetRoutes.isAllowed("100.128.0.0", 32))
        assertFalse(TailnetRoutes.isAllowed("fd7a:115c::", 32))
        assertFalse(TailnetRoutes.isAllowed("fd7a:115c:a1e1::1", 128))
    }

    @Test
    fun `garbage input is dropped instead of crashing the VPN setup`() {
        assertFalse(TailnetRoutes.isAllowed("not-an-ip", 32))
        assertFalse(TailnetRoutes.isAllowed("", 0))
        assertFalse(TailnetRoutes.isAllowed("100.64.0.1", 33))
        assertFalse(TailnetRoutes.isAllowed("100.64.0.1", -1))
    }
}
