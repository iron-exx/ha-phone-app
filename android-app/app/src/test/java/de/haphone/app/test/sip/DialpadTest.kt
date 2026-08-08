package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DialpadTest {
    @Test
    fun appendSanitizesEachCharacter() {
        val state = DialedNumberState()
        "1a50".forEach { state.append(it) }
        assertEquals("150", state.current)
    }

    @Test
    fun backspaceRemovesLastCharacter() {
        val state = DialedNumberState()
        "150".forEach { state.append(it) }
        state.backspace()
        assertEquals("15", state.current)
    }

    @Test
    fun clearEmptiesState() {
        val state = DialedNumberState()
        "150".forEach { state.append(it) }
        state.clear()
        assertEquals("", state.current)
    }

    @Test
    fun toCallUriBuildsTlsUri() {
        val state = DialedNumberState()
        "150".forEach { state.append(it) }
        assertEquals("sip:150@pbx.local:5061;transport=tls", state.toCallUri("pbx.local:5061"))
    }

    @Test
    fun toCallUriThrowsWhenEmpty() {
        assertThrows(IllegalArgumentException::class.java) { DialedNumberState().toCallUri("pbx.local:5061") }
    }
}
