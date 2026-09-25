package de.haphone.app.test.car

import de.haphone.app.test.calls.CallHistoryEntry
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * One callable number known to the car screens, pushed down from Dart after each
 * directory load (see [CarDirectoryStore]). Door flags mirror the Dart `Contact`.
 */
data class CarEntry(
    val number: String,
    val name: String,
    val isExtension: Boolean = true,
    val isDoor: Boolean = false,
    /** `door_open_remote`: the PBX opens this door by webhook (POST /api/mobile/door-open). */
    val openRemote: Boolean = false,
) {
    val displayName: String get() = name.ifBlank { number }
}

/** Presence + line state of one extension, as GET /api/mobile/presence reports it. */
data class CarPresence(val presence: String = "", val line: String = "")

/** Everything the car screens show: directory, favourites and the own number. */
data class CarDirectory(
    val entries: List<CarEntry> = emptyList(),
    val favorites: List<String> = emptyList(),
    val selfNumber: String = "",
) {
    fun find(number: String): CarEntry? = entries.firstOrNull { it.number == number }

    fun nameFor(number: String): String = find(number)?.name.orEmpty()

    /** Door name for the quick settings tile / shortcut dialog, e.g. "Haustür", else "Tür 16". */
    fun doorLabel(number: String): String = nameFor(number).trim().ifBlank { "Tür $number" }
}

/** Kind of the row icon. */
enum class CarIconKind { PERSON, DOOR, INCOMING, OUTGOING, MISSED, STAR }

/** A list row, independent of the Car App Library (so it is unit-testable). */
data class CarRow(
    val title: String,
    val subtitle: String,
    val number: String,
    val icon: CarIconKind,
    /** Rows of door stations open the door screen instead of dialling right away. */
    val opensDoor: Boolean = false,
)

/** What a door screen offers. [index] is the Home Assistant action index for [Kind.HA_ACTION]. */
data class DoorAction(val kind: Kind, val label: String, val index: Int = -1) {
    enum class Kind { CALL, OPEN, HA_ACTION }
}

/**
 * Pure list building for the Android Auto screens: sorting, labels, limits.
 * No Android / Car App Library types, so it runs in plain JVM unit tests.
 */
object CarLists {
    /** Car hosts cap lists anyway (ConstraintManager); this is the fallback. */
    const val DEFAULT_LIMIT = 6

    private val presenceLabels = mapOf(
        "available" to "verfügbar",
        "away" to "abwesend",
        "lunch" to "Mittagspause",
        "off_work" to "Feierabend",
        "do_not_disturb" to "nicht stören",
    )

    /** Same rule as the Dart ExtensionStatus: the line state wins over the presence. */
    fun statusLabel(p: CarPresence?): String = when (p?.line) {
        "busy" -> "telefoniert"
        "ringing" -> "klingelt"
        "offline" -> "offline"
        else -> presenceLabels[p?.presence].orEmpty()
    }

    /** 0 = reachable first ... 4 = offline last. Unknown presence counts as reachable. */
    fun rank(p: CarPresence?): Int = when {
        p?.line == "offline" -> 4
        p?.line == "busy" || p?.line == "ringing" -> 1
        p?.presence == "away" || p?.presence == "lunch" || p?.presence == "do_not_disturb" -> 2
        p?.presence == "off_work" -> 3
        else -> 0
    }

    private fun subtitle(number: String, p: CarPresence?): String {
        val label = statusLabel(p)
        return if (label.isEmpty()) number else "$number · $label"
    }

    private val byName = compareBy<CarEntry, String>(String.CASE_INSENSITIVE_ORDER) { it.displayName }
        .thenBy { it.number }

    /** Kontakte: own extensions without doors and without this device, reachable first. */
    fun contacts(dir: CarDirectory, presence: Map<String, CarPresence>, limit: Int = DEFAULT_LIMIT): List<CarRow> =
        dir.entries
            .filter { it.isExtension && !it.isDoor && it.number.isNotBlank() && it.number != dir.selfNumber }
            .sortedWith(compareBy<CarEntry> { rank(presence[it.number]) }.then(byName))
            .take(limit.coerceAtLeast(0))
            .map { CarRow(it.displayName, subtitle(it.number, presence[it.number]), it.number, CarIconKind.PERSON) }

    /** Favoriten in alphabetical order; unknown numbers still show (with the number as title). */
    fun favorites(dir: CarDirectory, presence: Map<String, CarPresence>, limit: Int = DEFAULT_LIMIT): List<CarRow> =
        dir.favorites
            .filter { it.isNotBlank() }
            .distinct()
            .map { dir.find(it) ?: CarEntry(it, "", isExtension = false) }
            .sortedWith(byName)
            .take(limit.coerceAtLeast(0))
            .map {
                val p = if (it.isExtension) presence[it.number] else null
                CarRow(
                    it.displayName, subtitle(it.number, p), it.number,
                    if (it.isDoor) CarIconKind.DOOR else CarIconKind.STAR,
                    opensDoor = it.isDoor,
                )
            }

    /** Haustür: every door station, by name. */
    fun doors(dir: CarDirectory, limit: Int = DEFAULT_LIMIT): List<CarRow> =
        dir.entries
            .filter { it.isDoor && it.number.isNotBlank() }
            .sortedWith(byName)
            .take(limit.coerceAtLeast(0))
            .map {
                CarRow(
                    it.displayName,
                    if (it.openRemote) "${it.number} · Tür öffnen möglich" else it.number,
                    it.number, CarIconKind.DOOR, opensDoor = true,
                )
            }

    /**
     * Door screen actions: calling always works; "Tür öffnen" only for doors the PBX opens
     * by webhook (a DTMF code needs an answered call, the car's in-call view has a dialpad);
     * then the door's Home Assistant actions by label.
     */
    fun doorActions(door: CarEntry, haLabels: List<String>): List<DoorAction> = buildList {
        add(DoorAction(DoorAction.Kind.CALL, "Anrufen"))
        if (door.openRemote) add(DoorAction(DoorAction.Kind.OPEN, "Tür öffnen"))
        haLabels.forEachIndexed { i, label -> if (label.isNotBlank()) add(DoorAction(DoorAction.Kind.HA_ACTION, label, i)) }
    }

    /** Verlauf: newest first (the store already is), names from the directory when the entry has none. */
    fun recents(
        history: List<CallHistoryEntry>,
        dir: CarDirectory,
        nowMs: Long,
        zone: ZoneId = ZoneId.systemDefault(),
        limit: Int = DEFAULT_LIMIT,
    ): List<CarRow> =
        history
            .filter { it.number.isNotBlank() }
            .sortedByDescending { it.startedAtMs }
            .take(limit.coerceAtLeast(0))
            .map { e ->
                val entry = dir.find(e.number)
                val name = e.name.ifBlank { entry?.name.orEmpty() }.ifBlank { e.number }
                val missed = e.direction == "incoming" && !e.answered
                val icon = when {
                    missed -> CarIconKind.MISSED
                    e.direction == "outgoing" -> CarIconKind.OUTGOING
                    else -> CarIconKind.INCOMING
                }
                CarRow(name, historySubtitle(e, nowMs, zone), e.number, icon)
            }

    fun historySubtitle(e: CallHistoryEntry, nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): String {
        val kind = when {
            e.direction == "outgoing" -> "Ausgehend"
            e.answered -> "Eingehend"
            else -> "Verpasst"
        }
        val parts = mutableListOf(kind, whenLabel(e.startedAtMs, nowMs, zone))
        if (e.answered) parts += duration(e.durationSec)
        return parts.joinToString(" · ")
    }

    private val time = DateTimeFormatter.ofPattern("HH:mm")
    private val dayTime = DateTimeFormatter.ofPattern("dd.MM. HH:mm")

    fun whenLabel(atMs: Long, nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): String {
        val at = Instant.ofEpochMilli(atMs).atZone(zone)
        val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        return when (at.toLocalDate()) {
            today -> at.format(time)
            today.minusDays(1) -> "gestern ${at.format(time)}"
            else -> at.format(dayTime)
        }
    }

    fun duration(sec: Long): String = "%d:%02d".format(sec / 60, sec % 60)
}
