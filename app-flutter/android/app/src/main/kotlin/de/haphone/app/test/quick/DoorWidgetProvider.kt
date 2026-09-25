package de.haphone.app.test.quick

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import de.haphone.app.test.HAPhoneTestApplication
import de.haphone.app.test.MainActivity
import de.haphone.app.test.R
import de.haphone.app.test.net.PbxTls
import org.json.JSONArray
import java.io.File
import java.time.Instant
import java.time.ZoneId
import kotlin.concurrent.thread

/**
 * Home screen widget: last doorbell picture with time (tap -> Klingel-Verlauf) and
 * "Tür öffnen" (always asks first, see [DoorOpenConfirmActivity]).
 *
 * Refreshed by the system (every 30 min), after each doorbell poll in Dart
 * (SipChannel.refreshDoorWidget) and after a missed ring. The last picture is kept in
 * the app's files so the widget renders without network.
 */
class DoorWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        render(context)
        refresh(context)
    }

    companion object {
        private const val TAG = "DoorWidget"
        private const val PREFS = "haphone_door_widget"
        private const val K_ID = "id"
        private const val K_AT = "at"
        private const val K_NAME = "name"
        private const val PICTURE = "door_widget.jpg"
        private const val MAX_PICTURE_PX = 480 // RemoteViews bitmaps must stay small

        private fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, DoorWidgetProvider::class.java))

        /** Fetches the latest ring from the PBX (background thread) and re-renders. No-op without widgets. */
        fun refresh(context: Context) {
            val app = context.applicationContext as? HAPhoneTestApplication ?: return
            if (ids(app).isEmpty()) return
            thread(name = "door-widget") {
                runCatching { fetchLatest(app) }.onFailure { Log.w(TAG, "refresh failed", it) }
                render(app)
            }
        }

        private fun fetchLatest(app: HAPhoneTestApplication) {
            val auth = app.getDeviceAuth()
            val host = auth["apiHost"].orEmpty()
            if (host.isBlank() || auth["deviceToken"].isNullOrBlank()) return
            val conn = open(host, auth, "/api/mobile/doorbell?limit=1")
            val latest = try {
                if (conn.responseCode != 200) return
                JSONArray(conn.inputStream.bufferedReader().readText()).optJSONObject(0) ?: return
            } finally {
                conn.disconnect()
            }
            val id = latest.getInt("id")
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getInt(K_ID, -1) == id && File(app.filesDir, PICTURE).exists()) return
            val picture = File(app.filesDir, PICTURE)
            if (latest.optBoolean("has_image")) {
                val img = open(host, auth, "/api/mobile/doorbell/$id/image")
                try {
                    if (img.responseCode == 200) img.inputStream.use { input -> picture.outputStream().use { input.copyTo(it) } }
                } finally {
                    img.disconnect()
                }
            } else {
                picture.delete()
            }
            val at = runCatching { Instant.parse(latest.getString("started_at")).toEpochMilli() }.getOrDefault(0L)
            prefs.edit().putInt(K_ID, id).putLong(K_AT, at).putString(K_NAME, latest.optString("door_name")).apply()
        }

        private fun open(host: String, auth: Map<String, String>, path: String) =
            PbxTls.open(host, path).apply {
                connectTimeout = 5_000
                readTimeout = 10_000
                setRequestProperty("X-Device-Id", auth["deviceId"].orEmpty())
                setRequestProperty("X-Device-Token", auth["deviceToken"].orEmpty())
            }

        /** Unpairing / other box: forget the picture and time. */
        fun clear(context: Context) {
            val app = context.applicationContext
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
            File(app.filesDir, PICTURE).delete()
            render(app)
        }

        /** Draws all widgets from the stored state (no network). */
        fun render(context: Context) {
            val app = context.applicationContext as? HAPhoneTestApplication ?: return
            val ids = ids(app)
            if (ids.isEmpty()) return
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val at = prefs.getLong(K_AT, 0L).takeIf { it > 0 }?.let(Instant::ofEpochMilli)
            val doors = app.doorCodes.openRemoteNumbers()
            val dir = app.carDirectory.load()
            val title = prefs.getString(K_NAME, null)?.takeIf { it.isNotBlank() }
                ?: doors.firstOrNull()?.let(dir::doorLabel) ?: "Tür"
            val views = RemoteViews(app.packageName, R.layout.widget_door).apply {
                setTextViewText(R.id.door_widget_title, title)
                setTextViewText(R.id.door_widget_time, DoorWidgetText.lastRing(at, Instant.now(), ZoneId.systemDefault()))
                val bitmap = loadPicture(File(app.filesDir, PICTURE))
                if (bitmap != null) {
                    setImageViewBitmap(R.id.door_widget_picture, bitmap)
                    setViewVisibility(R.id.door_widget_picture, View.VISIBLE)
                    setViewVisibility(R.id.door_widget_placeholder, View.GONE)
                } else {
                    setViewVisibility(R.id.door_widget_picture, View.GONE)
                    setViewVisibility(R.id.door_widget_placeholder, View.VISIBLE)
                }
                setViewVisibility(R.id.door_widget_open, if (doors.isEmpty()) View.GONE else View.VISIBLE)
                setOnClickPendingIntent(R.id.door_widget_open, activity(app, 1, Intent(app, DoorOpenConfirmActivity::class.java)))
                setOnClickPendingIntent(
                    R.id.door_widget_root,
                    activity(app, 2, Intent(app, MainActivity::class.java).putExtra("route", "doorbell")),
                )
            }
            AppWidgetManager.getInstance(app).updateAppWidget(ids, views)
        }

        private fun activity(context: Context, code: Int, intent: Intent): PendingIntent =
            PendingIntent.getActivity(
                context, code,
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        private fun loadPicture(file: File): Bitmap? {
            if (!file.exists()) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= MAX_PICTURE_PX) sample *= 2
            return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
        }
    }
}
