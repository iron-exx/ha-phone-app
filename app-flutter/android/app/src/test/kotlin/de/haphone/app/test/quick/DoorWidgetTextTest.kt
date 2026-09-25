package de.haphone.app.test.quick

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class DoorWidgetTextTest {
    private val zone = ZoneId.of("Europe/Berlin")
    private fun at(d: Int, h: Int, m: Int) = LocalDateTime.of(2026, 9, d, h, m).atZone(zone).toInstant()
    private val now = at(25, 18, 30)

    @Test
    fun `no ring yet`() {
        assertEquals("Noch nicht geklingelt", DoorWidgetText.lastRing(null, now, zone))
    }

    @Test
    fun `today, yesterday, older`() {
        assertEquals("zuletzt 15:13", DoorWidgetText.lastRing(at(25, 15, 13), now, zone))
        assertEquals("gestern 23:59", DoorWidgetText.lastRing(at(24, 23, 59), now, zone))
        assertEquals("am 23.09. 07:05", DoorWidgetText.lastRing(at(23, 7, 5), now, zone))
    }
}
