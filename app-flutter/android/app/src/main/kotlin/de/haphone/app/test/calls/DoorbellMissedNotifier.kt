package de.haphone.app.test.calls

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.core.app.NotificationCompat
import de.haphone.app.test.HAPhoneTestApplication
import de.haphone.app.test.MainActivity
import de.haphone.app.test.R
import org.json.JSONArray
import java.net.HttpURLConnection
import java.time.Instant
import kotlin.concurrent.thread

/**
 * "Es hat geklingelt": when a call ends unanswered, asks the PBX whether it was a door
 * station ring (doorbell history, HA-Phone 0.7.126+) and shows a notification with the
 * doorbell picture. Calls that are no ring (not in the PBX's history) are ignored, so the
 * PBX alone decides what a door is.
 */
object DoorbellMissedNotifier {
    private const val TAG = "DoorbellMissed"
    const val CHANNEL_ID = "haphone_doorbell"
    private const val NOTIFICATION_BASE_ID = 4000
    private const val SNAPSHOT_WAIT_MS = 3_000L // the PBX fetches the picture right when it rings
    private const val MAX_AGE_S = 180L

    fun onMissed(context: Context, number: String) {
        val app = context.applicationContext as? HAPhoneTestApplication ?: return
        thread(name = "doorbell-missed") {
            try {
                Thread.sleep(SNAPSHOT_WAIT_MS)
                val auth = app.getDeviceAuth()
                val host = auth["apiHost"].orEmpty()
                if (host.isBlank() || auth["deviceToken"].isNullOrBlank()) return@thread
                val event = latestMissedRing(host, auth, number) ?: return@thread
                val picture = if (event.hasImage) image(host, auth, event.id) else null
                show(app, event, picture)
            } catch (e: Exception) {
                Log.w(TAG, "missed ring notification failed", e)
            }
        }
    }

    private data class Ring(val id: Int, val door: String, val name: String, val at: Instant, val hasImage: Boolean)

    private fun get(host: String, auth: Map<String, String>, path: String): HttpURLConnection {
        val conn = de.haphone.app.test.net.PbxTls.open(host, path)
        conn.connectTimeout = 5_000
        conn.readTimeout = 10_000
        conn.setRequestProperty("X-Device-Id", auth["deviceId"].orEmpty())
        conn.setRequestProperty("X-Device-Token", auth["deviceToken"].orEmpty())
        return conn
    }

    private fun latestMissedRing(host: String, auth: Map<String, String>, number: String): Ring? {
        val conn = get(host, auth, "/api/mobile/doorbell?limit=5")
        try {
            if (conn.responseCode != 200) return null
            val arr = JSONArray(conn.inputStream.bufferedReader().readText())
            val now = Instant.now()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optString("door_number") != number || o.optString("answered_by").isNotEmpty()) continue
                val at = runCatching { Instant.parse(o.getString("started_at")) }.getOrNull() ?: continue
                if (now.epochSecond - at.epochSecond > MAX_AGE_S) return null
                return Ring(o.getInt("id"), number, o.optString("door_name"), at, o.optBoolean("has_image"))
            }
            return null
        } finally {
            conn.disconnect()
        }
    }

    private fun image(host: String, auth: Map<String, String>, id: Int): Bitmap? {
        val conn = get(host, auth, "/api/mobile/doorbell/$id/image")
        return try {
            if (conn.responseCode == 200) conn.inputStream.use { BitmapFactory.decodeStream(it) } else null
        } finally {
            conn.disconnect()
        }
    }

    private fun show(context: Context, ring: Ring, picture: Bitmap?) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Türklingel", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Es hat geklingelt, während du nicht abgenommen hast"
            },
        )
        val title = ring.name.ifBlank { "Tür ${ring.door}" }
        val clock = java.time.format.DateTimeFormatter.ofPattern("HH:mm")
            .format(ring.at.atZone(java.time.ZoneId.systemDefault()))
        val open = PendingIntent.getActivity(
            context, ring.id,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("route", "doorbell"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_haphone)
            .setContentTitle("Es hat geklingelt")
            .setContentText("$title · $clock")
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)
            .setContentIntent(open)
        if (picture != null) {
            builder.setLargeIcon(picture)
                .setStyle(NotificationCompat.BigPictureStyle().bigPicture(picture).bigLargeIcon(null as Bitmap?))
        }
        runCatching { nm.notify(NOTIFICATION_BASE_ID + ring.door.hashCode() % 1000, builder.build()) }
            .onFailure { Log.w(TAG, "notify failed (permission?)", it) }
        Log.i(TAG, "missed ring ${ring.id} at $title notified (picture=${picture != null})")
    }
}
