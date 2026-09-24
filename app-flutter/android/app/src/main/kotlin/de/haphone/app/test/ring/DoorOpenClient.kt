package de.haphone.app.test.ring

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * POST /api/mobile/door-open {extension} (HA-Phone 0.7.117) from the native ringing
 * screen, with the same device auth as DoorActionClient. Opens without answering.
 */
object DoorOpenClient {
    /** Blocking network call: run off the main thread. */
    fun open(apiHost: String, deviceId: String, deviceToken: String, extension: String): DoorOpenOutcome {
        if (apiHost.isBlank() || deviceToken.isBlank()) return DoorOpenOutcome.UNAUTHORIZED
        if (!DoorOpenOutcome.isValidExtension(extension)) return DoorOpenOutcome.UNREACHABLE
        return runCatching {
            val conn = URL("http://$apiHost/api/mobile/door-open").openConnection() as HttpURLConnection
            try {
                conn.requestMethod = "POST"
                conn.connectTimeout = 5_000
                conn.readTimeout = 10_000
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("X-Device-Id", deviceId)
                conn.setRequestProperty("X-Device-Token", deviceToken)
                conn.outputStream.use { it.write(JSONObject().put("extension", extension).toString().toByteArray()) }
                DoorOpenOutcome.fromHttpStatus(conn.responseCode)
            } finally {
                conn.disconnect()
            }
        }.getOrElse {
            android.util.Log.w("DoorOpenClient", "door-open failed", it)
            DoorOpenOutcome.UNREACHABLE
        }
    }
}
