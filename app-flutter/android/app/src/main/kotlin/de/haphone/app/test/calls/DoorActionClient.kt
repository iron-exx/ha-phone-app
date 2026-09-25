package de.haphone.app.test.calls

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection

/**
 * Home Assistant quick actions of door stations (labels only; the PBX keeps service
 * and entity). Labels come from Dart after each directory load; running one is a
 * POST /api/mobile/door-action with the device token, done natively so the ringing
 * screen works without the Flutter UI.
 */
class DoorActionClient(context: Context) {
    private val prefs = context.getSharedPreferences("haphone_door_actions", Context.MODE_PRIVATE)

    fun replaceAll(labelsByNumber: Map<String, List<String>>) {
        prefs.edit().clear().apply {
            labelsByNumber.forEach { (number, labels) ->
                if (number.isNotBlank() && labels.isNotEmpty()) putString(number, JSONArray(labels).toString())
            }
        }.apply()
    }

    fun labelsFor(number: String): List<String> = runCatching {
        val arr = JSONArray(prefs.getString(number, "[]"))
        (0 until arr.length()).map { arr.getString(it) }
    }.getOrDefault(emptyList())

    /** Blocking network call: run off the main thread. Returns null on success, else a German error. */
    fun run(apiHost: String, deviceId: String, deviceToken: String, number: String, index: Int): String? {
        if (apiHost.isBlank() || deviceToken.isBlank()) return "Gerät neu koppeln (QR-Code)"
        return runCatching {
            val conn = de.haphone.app.test.net.PbxTls.open(apiHost, "/api/mobile/door-action")
            conn.requestMethod = "POST"
            conn.connectTimeout = 5_000
            conn.readTimeout = 10_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("X-Device-Id", deviceId)
            conn.setRequestProperty("X-Device-Token", deviceToken)
            conn.outputStream.use { it.write(JSONObject().put("extension", number).put("index", index).toString().toByteArray()) }
            val code = conn.responseCode
            conn.disconnect()
            when {
                code in 200..299 -> null
                code == 401 -> "Gerät neu koppeln (QR-Code)"
                code == 404 -> "Aktion nicht gefunden (HA-Phone 0.7.111 nötig)"
                else -> "Home Assistant hat abgelehnt ($code)"
            }
        }.getOrElse { "Anlage nicht erreichbar" }
    }
}
