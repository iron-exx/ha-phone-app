package de.haphone.app.test.calls

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnswerGuardTest {
    @Test
    fun `only the first answer of a call goes through`() {
        val guard = AnswerGuard()
        assertTrue(guard.tryBegin(3)) // ringing screen
        assertFalse(guard.tryBegin(3)) // notification action a moment later
        assertFalse(guard.tryBegin(3)) // Telecom echo
        assertTrue(guard.isAnswered(3))
    }

    @Test
    fun `calls are guarded independently`() {
        val guard = AnswerGuard()
        assertTrue(guard.tryBegin(1))
        assertTrue(guard.tryBegin(2))
        assertFalse(guard.isAnswered(5))
    }

    @Test
    fun `a reused call id can be answered again after the call ended`() {
        val guard = AnswerGuard()
        guard.tryBegin(0)
        guard.forget(0)
        assertFalse(guard.isAnswered(0))
        assertTrue(guard.tryBegin(0))
    }
}
