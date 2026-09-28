package de.haphone.app.test.calls

import org.junit.Assert.assertEquals
import org.junit.Test

class VideoNumbersTest {
    @Test
    fun `number is taken from the sip uri`() {
        assertEquals("19", VideoNumbers.numberOf("sip:19@192.168.1.10:5061;transport=tls"))
        assertEquals("16", VideoNumbers.numberOf("sip:16@100.101.102.103:5063"))
    }
}
