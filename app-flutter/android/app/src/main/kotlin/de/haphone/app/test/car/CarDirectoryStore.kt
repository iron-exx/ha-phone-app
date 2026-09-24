package de.haphone.app.test.car

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native copy of the directory and the favourites for the Android Auto screens, which
 * run without the Flutter engine's UI. Dart pushes it after each directory load and
 * favourite change (SipChannel.setCarDirectory / setFavorites). No secrets in here.
 */
class CarDirectoryStore(context: Context) {
    private val prefs = context.getSharedPreferences("haphone_car_directory", Context.MODE_PRIVATE)
    @Volatile private var cache: CarDirectory? = null

    fun load(): CarDirectory = cache ?: read().also { cache = it }

    fun replaceEntries(entries: List<CarEntry>, selfNumber: String) {
        val next = load().copy(entries = entries.filter { it.number.isNotBlank() }, selfNumber = selfNumber)
        cache = next
        prefs.edit().putString(KEY_ENTRIES, encode(next.entries)).putString(KEY_SELF, selfNumber).apply()
    }

    fun replaceFavorites(numbers: List<String>) {
        val next = load().copy(favorites = numbers.filter { it.isNotBlank() }.distinct())
        cache = next
        prefs.edit().putString(KEY_FAVORITES, JSONArray(next.favorites).toString()).apply()
    }

    private fun read(): CarDirectory = runCatching {
        val arr = JSONArray(prefs.getString(KEY_ENTRIES, "[]"))
        val entries = (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            CarEntry(
                number = o.optString("number"),
                name = o.optString("name"),
                isExtension = o.optBoolean("ext", true),
                isDoor = o.optBoolean("door"),
                openRemote = o.optBoolean("openRemote"),
            )
        }
        val fav = JSONArray(prefs.getString(KEY_FAVORITES, "[]"))
        CarDirectory(entries, (0 until fav.length()).map { fav.getString(it) }, prefs.getString(KEY_SELF, "").orEmpty())
    }.getOrElse {
        android.util.Log.w("CarDirectoryStore", "corrupt car directory, starting fresh", it)
        CarDirectory()
    }

    private fun encode(entries: List<CarEntry>): String = JSONArray().apply {
        entries.forEach {
            put(
                JSONObject().put("number", it.number).put("name", it.name).put("ext", it.isExtension)
                    .put("door", it.isDoor).put("openRemote", it.openRemote),
            )
        }
    }.toString()

    companion object {
        private const val KEY_ENTRIES = "entries"
        private const val KEY_FAVORITES = "favorites"
        private const val KEY_SELF = "self"

        /** MethodChannel payload: list of maps {number, name, ext, door, openRemote}. */
        fun entriesFromChannel(raw: Any?): List<CarEntry> = (raw as? List<*>).orEmpty().mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val number = m["number"] as? String ?: return@mapNotNull null
            CarEntry(
                number = number,
                name = m["name"] as? String ?: "",
                isExtension = m["ext"] as? Boolean ?: true,
                isDoor = m["door"] as? Boolean ?: false,
                openRemote = m["openRemote"] as? Boolean ?: false,
            )
        }
    }
}
