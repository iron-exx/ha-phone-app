package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DialpadSanitizeTest {
    @Test
    fun sanitizeStripsEverythingExceptDigitsPlusStarHash() {
        assertEquals("123*#", DialString.sanitize("1a2!b3*#"))
    }

    @Test
    fun sanitizeOfEmptyStringIsEmpty() {
        assertEquals("", DialString.sanitize(""))
    }

    @Test
    fun toSipUriBuildsTlsTransportUri() {
        assertEquals("sip:50@pbx.local:5061;transport=tls", DialString.toSipUri("50", "pbx.local:5061"))
    }

    @Test
    fun toSipUriRejectsEmptySanitizedInput() {
        assertThrows(IllegalArgumentException::class.java) { DialString.toSipUri("", "pbx.local:5061") }
    }
}
