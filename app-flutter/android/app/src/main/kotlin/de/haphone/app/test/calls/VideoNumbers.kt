package de.haphone.app.test.calls

import android.content.Context

/**
 * Video-capable extensions (door stations, Indoorview), pushed from Dart after each
 * directory load. An outgoing call to one of them offers video (receive only, our camera
 * stays off), so the door camera shows up right away.
 */
object VideoNumbers {
    private const val PREFS = "haphone_video_numbers"
    private const val KEY = "numbers"
    @Volatile private var numbers: Set<String> = emptySet()

    fun load(context: Context) {
        numbers = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY, emptySet()).orEmpty()
    }

    fun replace(context: Context, next: Collection<String>) {
        numbers = next.filter { it.isNotBlank() }.toSet()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet(KEY, numbers).apply()
    }

    fun contains(number: String): Boolean = number in numbers

    /** "sip:19@192.168.1.10:5061;transport=tls" -> "19". */
    fun numberOf(uri: String): String = uri.removePrefix("sip:").substringBefore('@')
}
