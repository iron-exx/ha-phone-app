package de.haphone.app.test.calls

import android.content.Context

/**
 * Extension number -> DTMF door-open code, pushed down from Dart after each
 * /api/mobile/directory load. Kept natively because the ringing screen
 * (IncomingCallActivity) must show "Tür öffnen" without the Flutter engine.
 */
class DoorCodes(context: Context) {
    private val prefs = context.getSharedPreferences("haphone_door_codes", Context.MODE_PRIVATE)
    private val remotePrefs = context.getSharedPreferences("haphone_door_open_remote", Context.MODE_PRIVATE)

    fun replaceAll(codes: Map<String, String>) {
        prefs.edit().clear().apply {
            codes.forEach { (number, code) -> if (number.isNotBlank() && code.isNotBlank()) putString(number, code) }
        }.apply()
    }

    fun forNumber(number: String): String = prefs.getString(number, "").orEmpty()

    /** Doors the PBX opens by webhook (`door_open_remote`); replaces the stored set. */
    fun replaceOpenRemote(numbers: Collection<String>) {
        remotePrefs.edit().clear().putStringSet(KEY_REMOTE, numbers.filter { it.isNotBlank() }.toSet()).apply()
    }

    /** Doors that can be opened without a call (quick settings tile, shortcut). */
    fun openRemoteNumbers(): List<String> =
        remotePrefs.getStringSet(KEY_REMOTE, emptySet()).orEmpty().sorted()

    fun hasOpenRemote(number: String): Boolean =
        remotePrefs.getStringSet(KEY_REMOTE, emptySet()).orEmpty().contains(number)

    private companion object {
        const val KEY_REMOTE = "numbers"
    }
}
