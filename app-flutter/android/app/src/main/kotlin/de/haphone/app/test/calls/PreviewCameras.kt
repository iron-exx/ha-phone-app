package de.haphone.app.test.calls

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.json.JSONArray
import org.json.JSONObject

/** A Home Assistant camera the admin shared and this phone chose (Ich → Weitere Kameras). */
data class PreviewCamera(val entityId: String, val name: String)

/**
 * Native copy of the chosen extra cameras for the ringing screen (Dart pushes it via
 * `setPreviewCameras`), plus the blocking snapshot download from the PBX
 * (GET /api/mobile/cameras/{entity_id}/snapshot with the device token).
 */
class PreviewCameras(context: Context) {
    private val prefs = context.getSharedPreferences("haphone_preview_cameras", Context.MODE_PRIVATE)

    fun replaceAll(cameras: List<Map<*, *>>) {
        val arr = JSONArray()
        cameras.forEach { m ->
            val id = m["entity_id"] as? String ?: return@forEach
            if (!PreviewCameraPaths.isCameraEntity(id)) return@forEach
            arr.put(JSONObject().put("entity_id", id).put("name", (m["name"] as? String).orEmpty().ifBlank { id }))
        }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    fun load(): List<PreviewCamera> = runCatching {
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            PreviewCamera(o.getString("entity_id"), o.optString("name"))
        }
    }.getOrDefault(emptyList())

    /** Blocking network call: run off the main thread. Null on any failure. */
    fun snapshot(apiHost: String, deviceId: String, deviceToken: String, entityId: String): Bitmap? {
        if (apiHost.isBlank() || deviceToken.isBlank()) return null
        return runCatching {
            val conn = de.haphone.app.test.net.PbxTls.open(apiHost, PreviewCameraPaths.snapshot(entityId))
            conn.connectTimeout = 4_000
            conn.readTimeout = 6_000
            conn.setRequestProperty("X-Device-Id", deviceId)
            conn.setRequestProperty("X-Device-Token", deviceToken)
            try {
                if (conn.responseCode != 200) return@runCatching null
                val bytes = conn.inputStream.use { it.readBytes() }
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                val sample = PreviewCameraPaths.sampleSize(bounds.outWidth, MAX_PX)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            } finally {
                conn.disconnect()
            }
        }.getOrNull()
    }

    private companion object {
        const val KEY = "cameras"
        /** Enough for the enlarged view on a phone; keeps memory small. */
        const val MAX_PX = 960
    }
}

/** Pure helpers (JVM-tested). */
object PreviewCameraPaths {
    private val ENTITY = Regex("^camera\\.[a-z0-9_]{1,120}$")

    fun isCameraEntity(id: String) = ENTITY.matches(id)

    fun snapshot(entityId: String) = "/api/mobile/cameras/$entityId/snapshot"

    /** Power-of-two BitmapFactory sample size so the width stays >= [maxPx] / 2. */
    fun sampleSize(width: Int, maxPx: Int): Int {
        var sample = 1
        while (width / (sample * 2) >= maxPx) sample *= 2
        return sample
    }
}
