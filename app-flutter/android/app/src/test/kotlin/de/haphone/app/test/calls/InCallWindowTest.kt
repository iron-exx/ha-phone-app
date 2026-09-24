package de.haphone.app.test.calls

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class InCallWindowTest {
    private val seen = mutableListOf<Boolean>()
    private val listener = InCallWindow.Listener { seen.add(it) }

    @Before fun setUp() = InCallWindow.reset()
    @After fun tearDown() = InCallWindow.reset()

    @Test
    fun `starts without a call`() {
        assertFalse(InCallWindow.isActive)
    }

    @Test
    fun `observe reports the current state right away`() {
        InCallWindow.setActive(true)
        InCallWindow.observe(listener)
        assertEquals(listOf(true), seen)
    }

    @Test
    fun `notifies only on real changes`() {
        InCallWindow.observe(listener)
        InCallWindow.setActive(true)
        InCallWindow.setActive(true)
        InCallWindow.setActive(false)
        InCallWindow.setActive(false)
        assertEquals(listOf(false, true, false), seen)
    }

    @Test
    fun `call end resets the flag so the app is not usable over the keyguard`() {
        InCallWindow.setActive(true)
        InCallWindow.setActive(false)
        assertFalse(InCallWindow.isActive)
    }

    @Test
    fun `removed listener hears nothing more`() {
        InCallWindow.observe(listener)
        InCallWindow.remove(listener)
        InCallWindow.setActive(true)
        assertEquals(listOf(false), seen)
        assertTrue(InCallWindow.isActive)
    }

    @Test
    fun `a listener may remove itself while being notified`() {
        lateinit var self: InCallWindow.Listener
        self = InCallWindow.Listener { active -> if (active) InCallWindow.remove(self) }
        InCallWindow.observe(self)
        InCallWindow.observe(listener)
        InCallWindow.setActive(true)
        assertEquals(listOf(false, true), seen)
    }
}
