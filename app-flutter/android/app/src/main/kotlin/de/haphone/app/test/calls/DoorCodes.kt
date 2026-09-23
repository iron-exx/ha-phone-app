package de.haphone.app.test.calls

import android.content.Context

/**
 * Extension number -> DTMF door-open code, pushed down from Dart after each
 * /api/mobile/directory load. Kept natively because the ringing screen
 * (IncomingCallActivity) must show "Tür öffnen" without the Flutter engine.
 */
class DoorCodes(context: Context) {
    private val prefs = context.getSharedPreferences("haphone_door_codes", Context.MODE_PRIVATE)

    fun replaceAll(codes: Map<String, String>) {
        prefs.edit().clear().apply {
            codes.forEach { (number, code) -> if (number.isNotBlank() && code.isNotBlank()) putString(number, code) }
        }.apply()
    }

    fun forNumber(number: String): String = prefs.getString(number, "").orEmpty()
}
