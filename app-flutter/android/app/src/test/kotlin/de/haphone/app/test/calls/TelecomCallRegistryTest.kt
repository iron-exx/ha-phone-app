package de.haphone.app.test.calls

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TelecomCallRegistryTest {
    private val registry = TelecomCallRegistry<String>()

    @Test
    fun `registered call is found by its SIP call and released with its scope`() {
        val token = registry.begin(7)
        assertTrue(registry.attach(token, "scope7"))
        assertEquals(token, registry.tokenFor(7))
        assertEquals(7, registry.sipCallIdFor(token))
        assertEquals("scope7", registry.current())
        assertEquals("scope7", registry.releaseFor(7))
        assertFalse(registry.isLive(token))
        assertNull(registry.current())
    }

    @Test
    fun `call released before Telecom registered it is disconnected on arrival`() {
        val token = registry.begin(4)
        assertNull(registry.release(token)) // SIP call ended, no scope yet
        assertFalse(registry.attach(token, "late")) // -> caller disconnects "late"
        assertFalse(registry.isLive(token))
        assertNull(registry.current())
        // A second, unrelated attach with that token does not resurrect it either.
        assertFalse(registry.attach(token, "again"))
    }

    @Test
    fun `releaseAll returns registered scopes and marks pending ones`() {
        val a = registry.begin(1).also { registry.attach(it, "a") }
        val pending = registry.begin(2)
        assertEquals(listOf("a"), registry.releaseAll())
        assertFalse(registry.isLive(a))
        assertFalse(registry.attach(pending, "b"))
        assertTrue(registry.isEmpty)
    }

    @Test
    fun `each call keeps its own scope`() {
        val first = registry.begin(1).also { registry.attach(it, "one") }
        val second = registry.begin(2).also { registry.attach(it, "two") }
        assertEquals("two", registry.current())
        assertEquals("one", registry.scopeFor(first))
        assertEquals("two", registry.release(second))
        assertEquals("one", registry.current())
    }

    @Test
    fun `outgoing call binds its SIP id after registration`() {
        val token = registry.begin(null, incoming = false)
        registry.attach(token, "out")
        assertNull(registry.sipCallIdFor(token))
        registry.bindSipCall(token, 9)
        assertEquals(token, registry.tokenFor(9))
        // An outgoing call is never mistaken for a ringing push call.
        assertFalse(registry.hasUnansweredWithoutSipCall())
        assertNull(registry.adoptPushCall(3))
    }

    @Test
    fun `push call is adopted by its INVITE instead of a second Telecom call`() {
        val push = registry.begin(null)
        assertTrue(registry.hasUnansweredWithoutSipCall())
        assertEquals(push, registry.adoptPushCall(5))
        assertEquals(5, registry.sipCallIdFor(push))
        assertFalse(registry.hasUnansweredWithoutSipCall())
        assertNull(registry.adoptPushCall(6))
    }

    @Test
    fun `answered state is per call`() {
        val token = registry.begin(1)
        assertFalse(registry.isAnswered(token))
        registry.markAnswered(token) // before the scope arrived
        registry.attach(token, "s")
        assertTrue(registry.isAnswered(token))
        assertFalse(registry.isAnswered(registry.begin(2)))
    }

    @Test
    fun `Telecom call moves to the remaining SIP call when its own ends`() {
        val token = registry.begin(1).also { registry.attach(it, "s") }
        registry.moveSipCall(ended = 1, remaining = 2)
        assertNull(registry.tokenFor(1))
        assertEquals(token, registry.tokenFor(2))
    }

    @Test
    fun `failed registration is forgotten without a scope`() {
        val token = registry.begin(1)
        registry.forget(token)
        assertFalse(registry.isLive(token))
        assertFalse(registry.attach(token, "x"))
    }
}
