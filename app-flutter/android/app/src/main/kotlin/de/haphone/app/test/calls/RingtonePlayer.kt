package de.haphone.app.test.calls

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log

/**
 * Plays the incoming-call alert ourselves: the "Anrufe" notification channel is silent
 * (a channel sound plays once and cannot loop). Loops the user's default ringtone and a
 * repeating vibration while a call rings, or a call-waiting beep in the earpiece while a
 * second call knocks. What plays is decided by [RingAlert.decide] (ringer mode, DND).
 *
 * Main thread only. [stop] is idempotent and is called from every end path (answer,
 * decline, remote cancel, answered elsewhere, disconnect, Telecom teardown, timeout).
 */
object RingtonePlayer {
    const val TAG = "Ringtone"
    private const val WAITING_TONE_VOLUME = 80
    /** API 26/27 have no Ringtone.isLooping: re-start the ringtone when it finished. */
    private const val LOOP_POLL_MS = 1_000L

    private val main = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var waitingTone: ToneGenerator? = null
    private val loopPoll = object : Runnable {
        override fun run() {
            val r = ringtone ?: return
            if (!r.isPlaying) runCatching { r.play() }
            main.postDelayed(this, LOOP_POLL_MS)
        }
    }

    private val ringAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** An incoming call is shown (ringing screen / notification). */
    fun startRinging(context: Context, channelId: String) {
        if (ringtone != null || vibrator != null) return
        val alert = currentAlert(context, channelId, waiting = false)
        Log.i(TAG, "ringing: $alert")
        if (alert.sound) startRingtone(context)
        if (alert.vibrate) startVibration(context)
    }

    /** A second call knocks during a call: short beep cadence in the earpiece. */
    fun startWaitingBeep(context: Context, channelId: String) {
        if (waitingTone != null) return
        if (!currentAlert(context, channelId, waiting = true).waitingBeep) return
        waitingTone = runCatching {
            ToneGenerator(AudioManager.STREAM_VOICE_CALL, WAITING_TONE_VOLUME).also {
                it.startTone(ToneGenerator.TONE_SUP_CALL_WAITING)
            }
        }.onFailure { Log.w(TAG, "call waiting tone unavailable", it) }.getOrNull()
    }

    fun stopWaitingBeep() {
        waitingTone?.let { tone ->
            runCatching { tone.stopTone() }
            runCatching { tone.release() }
        }
        waitingTone = null
    }

    /** Stops ringtone, vibration and waiting beep. Safe to call any time, repeatedly. */
    fun stop() {
        main.removeCallbacks(loopPoll)
        ringtone?.let { r -> runCatching { r.stop() } }
        ringtone = null
        vibrator?.let { v -> runCatching { v.cancel() } }
        vibrator = null
        stopWaitingBeep()
    }

    val isRinging: Boolean get() = ringtone != null || vibrator != null

    private fun currentAlert(context: Context, channelId: String, waiting: Boolean): RingAlert {
        val audio = context.getSystemService(AudioManager::class.java)
        val notifications = context.getSystemService(NotificationManager::class.java)
        val ringerMode = when (audio?.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> RingerMode.SILENT
            AudioManager.RINGER_MODE_VIBRATE -> RingerMode.VIBRATE
            else -> RingerMode.NORMAL
        }
        val filter = notifications?.currentInterruptionFilter ?: NotificationManager.INTERRUPTION_FILTER_ALL
        val dndActive = filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
        val bypass = runCatching { notifications?.getNotificationChannel(channelId)?.canBypassDnd() == true }
            .getOrDefault(false)
        // "Beim Klingeln vibrieren"; unreadable on some OEMs -> vibrate like most phones do.
        val vibrateWhenRinging = runCatching {
            Settings.System.getInt(context.contentResolver, "vibrate_when_ringing", 1) != 0
        }.getOrDefault(true)
        return RingAlert.decide(ringerMode, dndActive, bypass, vibrateWhenRinging, waiting)
    }

    private fun startRingtone(context: Context) {
        val uri = runCatching { RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE) }
            .getOrNull() ?: Settings.System.DEFAULT_RINGTONE_URI
        val r = runCatching { RingtoneManager.getRingtone(context, uri) }.getOrNull()
            ?: runCatching {
                RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            }.getOrNull()
        if (r == null) {
            Log.w(TAG, "no ringtone available ($uri)")
            return
        }
        runCatching {
            r.audioAttributes = ringAttributes
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) r.isLooping = true
            r.play()
            ringtone = r
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) main.postDelayed(loopPoll, LOOP_POLL_MS)
        }.onFailure { Log.w(TAG, "ringtone failed to play", it) }
    }

    private fun startVibration(context: Context) {
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
        if (v == null || !v.hasVibrator()) return
        runCatching {
            @Suppress("DEPRECATION") // vibrate(effect, attributes): the only API 26+ way to mark it as ringing.
            v.vibrate(VibrationEffect.createWaveform(RingAlert.VIBRATION_PATTERN_MS, 0), ringAttributes)
            vibrator = v
        }.onFailure { Log.w(TAG, "vibration failed", it) }
    }
}
