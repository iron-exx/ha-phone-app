package de.haphone.app.test.ring

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalTime

class RingLayoutTest {
    private fun input(
        callType: String? = "audio",
        number: String = "11",
        name: String = "",
        doorCode: String = "",
        remote: Boolean = false,
        actions: List<String> = emptyList(),
        locked: Boolean = false,
    ) = RingInput(callType, number, name, doorCode, remote, actions, locked)

    @Test
    fun `plain audio call from a colleague is the normal variant without door controls`() {
        val l = RingLayouts.of(input(name = "Sandro Ahrens"))
        assertEquals(RingVariant.NORMAL, l.variant)
        assertEquals(RingLayouts.NORMAL_TITLE, l.title)
        assertEquals("Sandro Ahrens", l.displayName)
        assertEquals("11", l.displayNumber)
        assertFalse(l.showVideo)
        assertFalse(l.showSlider)
        assertFalse(l.showVideoAnswer)
        assertTrue(l.doorActions.isEmpty())
    }

    @Test
    fun `unknown name shows the number once`() {
        val l = RingLayouts.of(input(number = "0301234"))
        assertEquals("0301234", l.displayName)
        assertEquals("", l.displayNumber)
    }

    @Test
    fun `door with webhook and code prefers the webhook`() {
        val l = RingLayouts.of(input(callType = "video", number = "16", name = "Haustür", doorCode = "*1", remote = true, actions = listOf("Licht")))
        assertEquals(RingVariant.DOOR, l.variant)
        assertEquals(RingLayouts.DOOR_TITLE, l.title)
        assertEquals(DoorOpenMethod.WEBHOOK, l.openMethod)
        assertTrue(l.showSlider)
        assertTrue(l.showVideo)
        assertTrue(l.showLiveChip)
        assertEquals(listOf("Licht"), l.doorActions)
    }

    @Test
    fun `door with only a DTMF code answers to open`() {
        assertEquals(DoorOpenMethod.DTMF, RingLayouts.of(input(doorCode = "*1")).openMethod)
    }

    @Test
    fun `door station without video has no live chip but is still a door`() {
        val l = RingLayouts.of(input(callType = "audio", doorCode = "*1"))
        assertEquals(RingVariant.DOOR, l.variant)
        assertFalse(l.showVideo)
        assertFalse(l.showLiveChip)
    }

    @Test
    fun `door with only HA actions shows chips but no slider`() {
        val l = RingLayouts.of(input(actions = listOf("Garage")))
        assertEquals(RingVariant.DOOR, l.variant)
        assertEquals(DoorOpenMethod.NONE, l.openMethod)
        assertFalse(l.showSlider)
        assertEquals(listOf("Garage"), l.doorActions)
    }

    @Test
    fun `video call from a non-door gets the picture layout without door title or slider`() {
        val l = RingLayouts.of(input(callType = "video", name = "Kollege"))
        assertEquals(RingVariant.DOOR, l.variant)
        assertEquals(RingLayouts.VIDEO_TITLE, l.title)
        assertFalse(l.isDoorStation)
        assertFalse(l.showSlider)
    }

    @Test
    fun `locked chip follows the keyguard`() {
        assertTrue(RingLayouts.of(input(locked = true)).showLockedChip)
        assertFalse(RingLayouts.of(input(locked = false)).showLockedChip)
    }

    @Test
    fun `open method decision`() {
        assertEquals(DoorOpenMethod.WEBHOOK, RingLayouts.openMethod(true, ""))
        assertEquals(DoorOpenMethod.WEBHOOK, RingLayouts.openMethod(true, "*1"))
        assertEquals(DoorOpenMethod.DTMF, RingLayouts.openMethod(false, "*1"))
        assertEquals(DoorOpenMethod.NONE, RingLayouts.openMethod(false, " "))
    }

    @Test
    fun `meta line is number and time`() {
        assertEquals("16 · 10:44", RingLayouts.meta("16", LocalTime.of(10, 44, 59)))
        assertEquals("07:05", RingLayouts.meta("", LocalTime.of(7, 5)))
    }

    @Test
    fun `initials`() {
        assertEquals("SA", RingLayouts.initials("Sandro Ahrens"))
        assertEquals("H", RingLayouts.initials("haustür"))
        assertEquals("#", RingLayouts.initials("+49 301234"))
        assertEquals("?", RingLayouts.initials("  "))
    }
}
