package de.haphone.app.test.calls

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists the call history in plain SharedPreferences (no secrets in it). Recorded
 * natively so calls that ring while the Flutter UI is not attached still show up.
 * Main thread only.
 */
class CallHistoryStore(context: Context) {
    private val prefs = context.getSharedPreferences("haphone_call_history", Context.MODE_PRIVATE)
    private var cache: List<CallHistoryEntry>? = null

    fun all(): List<CallHistoryEntry> = cache ?: load().also { cache = it }

    fun update(transform: (List<CallHistoryEntry>) -> List<CallHistoryEntry>) {
        val next = transform(all())
        cache = next
        prefs.edit().putString(KEY, encode(next)).apply()
    }

    private fun load(): List<CallHistoryEntry> = runCatching {
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            CallHistoryEntry(
                id = o.getString("id"),
                number = o.optString("number"),
                name = o.optString("name"),
                direction = o.optString("direction"),
                video = o.optBoolean("video"),
                startedAtMs = o.optLong("startedAtMs"),
                answeredAtMs = o.optLong("answeredAtMs"),
                endedAtMs = o.optLong("endedAtMs"),
            )
        }
    }.getOrElse {
        android.util.Log.w("CallHistoryStore", "corrupt call history, starting fresh", it)
        emptyList()
    }

    private fun encode(entries: List<CallHistoryEntry>): String {
        val arr = JSONArray()
        entries.forEach { e ->
            arr.put(
                JSONObject()
                    .put("id", e.id)
                    .put("number", e.number)
                    .put("name", e.name)
                    .put("direction", e.direction)
                    .put("video", e.video)
                    .put("startedAtMs", e.startedAtMs)
                    .put("answeredAtMs", e.answeredAtMs)
                    .put("endedAtMs", e.endedAtMs),
            )
        }
        return arr.toString()
    }

    private companion object {
        const val KEY = "entries"
    }
}
