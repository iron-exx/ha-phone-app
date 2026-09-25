package de.haphone.app.test.quick

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Texts of the home screen door widget (pure, unit-tested). */
object DoorWidgetText {
    private val TIME = DateTimeFormatter.ofPattern("HH:mm")
    private val DATE_TIME = DateTimeFormatter.ofPattern("dd.MM. HH:mm")

    fun lastRing(at: Instant?, now: Instant, zone: ZoneId): String {
        if (at == null) return "Noch nicht geklingelt"
        val day = at.atZone(zone).toLocalDate()
        val today = now.atZone(zone).toLocalDate()
        val t = at.atZone(zone)
        return when (day) {
            today -> "zuletzt ${TIME.format(t)}"
            today.minusDays(1) -> "gestern ${TIME.format(t)}"
            else -> "am ${DATE_TIME.format(t)}"
        }
    }
}
