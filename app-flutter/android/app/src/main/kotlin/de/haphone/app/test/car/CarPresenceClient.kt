package de.haphone.app.test.car

import org.json.JSONObject
import java.net.HttpURLConnection

/**
 * GET /api/mobile/presence with the device auth, for the car's Kontakte list (the Dart
 * poller only runs while the phone UI is in the foreground).
 */
object CarPresenceClient {
    /** Blocking network call: run off the main thread. Empty map when unreachable. */
    fun fetch(apiHost: String, deviceId: String, deviceToken: String): Map<String, CarPresence> {
        if (apiHost.isBlank() || deviceToken.isBlank()) return emptyMap()
        return runCatching {
            val conn = de.haphone.app.test.net.PbxTls.open(apiHost, "/api/mobile/presence")
            try {
                conn.connectTimeout = 5_000
                conn.readTimeout = 8_000
                conn.setRequestProperty("X-Device-Id", deviceId)
                conn.setRequestProperty("X-Device-Token", deviceToken)
                if (conn.responseCode !in 200..299) return@runCatching emptyMap()
                parse(conn.inputStream.bufferedReader().use { it.readText() })
            } finally {
                conn.disconnect()
            }
        }.getOrElse {
            android.util.Log.w("CarPresenceClient", "presence failed", it)
            emptyMap()
        }
    }

    private fun parse(body: String): Map<String, CarPresence> {
        val json = JSONObject(body)
        val out = mutableMapOf<String, CarPresence>()
        val arr = json.optJSONArray("extensions")
        for (i in 0 until (arr?.length() ?: 0)) {
            val o = arr!!.optJSONObject(i) ?: continue
            val number = o.optString("number")
            if (number.isNotEmpty()) out[number] = CarPresence(o.optString("presence"), o.optString("line"))
        }
        return out
    }
}
