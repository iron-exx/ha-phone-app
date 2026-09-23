package de.haphone.app.test.calls

/** One call in the local call history. Times are epoch millis; [answeredAtMs] 0 = never answered. */
data class CallHistoryEntry(
    val id: String,
    val number: String,
    val name: String,
    val direction: String, // "incoming" | "outgoing"
    val video: Boolean,
    val startedAtMs: Long,
    val answeredAtMs: Long = 0,
    val endedAtMs: Long = 0,
) {
    val answered: Boolean get() = answeredAtMs > 0

    val durationSec: Long
        get() = if (answered && endedAtMs >= answeredAtMs) (endedAtMs - answeredAtMs) / 1000 else 0

    fun toChannelMap(): Map<String, Any> = mapOf(
        "id" to id,
        "number" to number,
        "name" to name,
        "direction" to direction,
        "answered" to answered,
        "video" to video,
        "startedAtMs" to startedAtMs,
        "durationSec" to durationSec,
    )
}

/**
 * Pure list logic of the call history (newest first, capped). Returns new lists,
 * never mutates; persistence lives in [CallHistoryStore].
 */
object CallHistory {
    const val MAX_ENTRIES = 200

    fun add(entries: List<CallHistoryEntry>, entry: CallHistoryEntry): List<CallHistoryEntry> =
        (listOf(entry) + entries.filter { it.id != entry.id }).take(MAX_ENTRIES)

    fun markAnswered(entries: List<CallHistoryEntry>, id: String, atMs: Long): List<CallHistoryEntry> =
        entries.map { if (it.id == id && !it.answered) it.copy(answeredAtMs = atMs) else it }

    fun markEnded(entries: List<CallHistoryEntry>, id: String, atMs: Long): List<CallHistoryEntry> =
        entries.map { if (it.id == id && it.endedAtMs == 0L) it.copy(endedAtMs = atMs) else it }

    fun remove(entries: List<CallHistoryEntry>, id: String): List<CallHistoryEntry> =
        entries.filter { it.id != id }
}
