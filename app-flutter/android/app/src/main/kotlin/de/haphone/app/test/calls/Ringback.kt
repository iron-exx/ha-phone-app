package de.haphone.app.test.calls

import android.media.AudioManager
import android.media.ToneGenerator

/**
 * Ringback ("Tuten") for outgoing calls. PJSIP plays nothing by itself, so after dialing
 * the caller heard silence until the other side answered. Main thread only.
 */
object Ringback {
    private const val VOLUME = 80
    private var tone: ToneGenerator? = null

    /** Outgoing call reached EARLY (180/183): the callee is ringing. */
    fun shouldPlay(isOutgoing: Boolean, isEarly: Boolean): Boolean = isOutgoing && isEarly

    fun start() {
        if (tone != null) return
        tone = runCatching {
            ToneGenerator(AudioManager.STREAM_VOICE_CALL, VOLUME).also {
                // CEPT supervisory ringtone: 425 Hz, 1 s on / 4 s off (German "Freizeichen").
                it.startTone(ToneGenerator.TONE_SUP_RINGTONE)
            }
        }.onFailure { android.util.Log.w("PJSIP", "ringback tone unavailable", it) }.getOrNull()
    }

    fun stop() {
        tone?.let {
            it.stopTone()
            it.release()
        }
        tone = null
    }
}
