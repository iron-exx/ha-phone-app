package de.haphone.app.test.car

import de.haphone.app.test.calls.CallHistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class CarListsTest {
    private val zone = ZoneId.of("Europe/Berlin")
    private fun ms(y: Int, mo: Int, d: Int, h: Int, mi: Int) =
        LocalDateTime.of(y, mo, d, h, mi).atZone(zone).toInstant().toEpochMilli()

    private val dir = CarDirectory(
        entries = listOf(
            CarEntry("11", "sandro"),
            CarEntry("12", "Büro"),
            CarEntry("13", "Test"),
            CarEntry("14", "anna"),
            CarEntry("16", "Haustür", isDoor = true, openRemote = true),
            CarEntry("17", "Garage", isDoor = true),
            CarEntry("0301234", "Pizza", isExtension = false),
        ),
        favorites = listOf("16", "11", "0301234", "999", "11"),
        selfNumber = "13",
    )

    @Test
    fun `contacts leave out doors, phonebook and the own extension`() {
        val rows = CarLists.contacts(dir, emptyMap(), limit = 10)
        assertEquals(listOf("14", "12", "11"), rows.map { it.number })
    }

    @Test
    fun `contacts sort reachable first, offline last, then by name`() {
        val presence = mapOf(
            "11" to CarPresence("available", "idle"),
            "12" to CarPresence("available", "offline"),
            "14" to CarPresence("available", "busy"),
        )
        val rows = CarLists.contacts(dir, presence, limit = 10)
        assertEquals(listOf("11", "14", "12"), rows.map { it.number })
        assertEquals("11 · verfügbar", rows[0].subtitle)
        assertEquals("14 · telefoniert", rows[1].subtitle)
        assertEquals("12 · offline", rows[2].subtitle)
    }

    @Test
    fun `presence rank orders away and off work between busy and offline`() {
        assertTrue(CarLists.rank(CarPresence("available", "idle")) < CarLists.rank(CarPresence("", "busy")))
        assertTrue(CarLists.rank(CarPresence("", "ringing")) < CarLists.rank(CarPresence("lunch", "idle")))
        assertTrue(CarLists.rank(CarPresence("do_not_disturb", "")) < CarLists.rank(CarPresence("off_work", "")))
        assertTrue(CarLists.rank(CarPresence("off_work", "")) < CarLists.rank(CarPresence("available", "offline")))
        assertEquals(0, CarLists.rank(null))
    }

    @Test
    fun `status label prefers the line state`() {
        assertEquals("telefoniert", CarLists.statusLabel(CarPresence("available", "busy")))
        assertEquals("nicht stören", CarLists.statusLabel(CarPresence("do_not_disturb", "idle")))
        assertEquals("", CarLists.statusLabel(null))
    }

    @Test
    fun `contacts respect the host list limit`() {
        assertEquals(2, CarLists.contacts(dir, emptyMap(), limit = 2).size)
        assertEquals(0, CarLists.contacts(dir, emptyMap(), limit = -1).size)
    }

    @Test
    fun `favorites are deduplicated, sorted and keep unknown numbers`() {
        val rows = CarLists.favorites(dir, emptyMap(), limit = 10)
        assertEquals(listOf("999", "16", "0301234", "11"), rows.map { it.number })
        assertEquals("999", rows[0].title)
        val door = rows.single { it.number == "16" }
        assertTrue(door.opensDoor)
        assertEquals(CarIconKind.DOOR, door.icon)
        assertFalse(rows.single { it.number == "11" }.opensDoor)
    }

    @Test
    fun `doors list only door stations and hint at remote opening`() {
        val rows = CarLists.doors(dir, limit = 10)
        assertEquals(listOf("17", "16"), rows.map { it.number })
        assertEquals("16 · Tür öffnen möglich", rows[1].subtitle)
        assertEquals("17", rows[0].subtitle)
        assertTrue(rows.all { it.opensDoor })
    }

    @Test
    fun `door actions offer opening only with door_open_remote`() {
        val remote = CarLists.doorActions(CarEntry("16", "Haustür", isDoor = true, openRemote = true), listOf("Licht", "", "Tor"))
        assertEquals(
            listOf(DoorAction.Kind.CALL, DoorAction.Kind.OPEN, DoorAction.Kind.HA_ACTION, DoorAction.Kind.HA_ACTION),
            remote.map { it.kind },
        )
        assertEquals(listOf(0, 2), remote.filter { it.kind == DoorAction.Kind.HA_ACTION }.map { it.index })
        assertEquals("Tür öffnen", remote[1].label)

        val dtmfOnly = CarLists.doorActions(CarEntry("17", "Garage", isDoor = true), emptyList())
        assertEquals(listOf(DoorAction.Kind.CALL), dtmfOnly.map { it.kind })
    }

    @Test
    fun `recents are newest first with names and missed calls marked`() {
        val now = ms(2026, 9, 24, 18, 0)
        val history = listOf(
            CallHistoryEntry("a", "11", "", "outgoing", false, ms(2026, 9, 24, 9, 5), ms(2026, 9, 24, 9, 5), ms(2026, 9, 24, 9, 7) + 5_000),
            CallHistoryEntry("b", "16", "", "incoming", true, ms(2026, 9, 24, 17, 30)),
            CallHistoryEntry("c", "0171", "Paket", "incoming", false, ms(2026, 9, 23, 12, 0), ms(2026, 9, 23, 12, 0), ms(2026, 9, 23, 12, 0) + 61_000),
            CallHistoryEntry("d", "", "", "incoming", false, ms(2026, 9, 1, 8, 0)),
        )
        val rows = CarLists.recents(history, dir, now, zone, limit = 10)
        assertEquals(listOf("16", "11", "0171"), rows.map { it.number })
        assertEquals("Haustür", rows[0].title)
        assertEquals(CarIconKind.MISSED, rows[0].icon)
        assertEquals("Verpasst · 17:30", rows[0].subtitle)
        assertEquals("Ausgehend · 09:05 · 2:05", rows[1].subtitle)
        assertEquals(CarIconKind.OUTGOING, rows[1].icon)
        assertEquals("Paket", rows[2].title)
        assertEquals("Eingehend · gestern 12:00 · 1:01", rows[2].subtitle)
    }

    @Test
    fun `older calls show the date`() {
        assertEquals("01.09. 08:00", CarLists.whenLabel(ms(2026, 9, 1, 8, 0), ms(2026, 9, 24, 18, 0), zone))
    }
}
