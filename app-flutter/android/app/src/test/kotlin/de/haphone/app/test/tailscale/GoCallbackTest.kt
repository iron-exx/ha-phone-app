package de.haphone.app.test.tailscale

import org.junit.Assert.assertEquals
import org.junit.Test

class GoCallbackTest {
    @Test
    fun `returns the block's value`() {
        assertEquals("ok", goSafe("t", "fallback") { "ok" })
    }

    @Test
    fun `never lets an exception or error escape to Go`() {
        assertEquals("[]", goSafe("t", "[]") { throw IllegalStateException("keystore") })
        assertEquals(false, goSafe("t", false) { throw NoSuchMethodError("setMetered") })
    }
}
