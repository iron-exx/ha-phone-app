package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ContactParamsTest {
    @Test
    fun `device id becomes a contact uri parameter`() {
        assertEquals(";haphone-dev=17", contactParams("17"))
        assertEquals(";haphone-dev=17", contactParams(" 17 "))
    }

    @Test
    fun `no or odd device id adds nothing`() {
        assertNull(contactParams(""))
        assertNull(contactParams("17;transport=udp"))
        assertNull(contactParams("abc"))
    }
}
