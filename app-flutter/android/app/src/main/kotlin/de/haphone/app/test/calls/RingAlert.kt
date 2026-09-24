package de.haphone.app.test.calls

/** AudioManager.RINGER_MODE_* without the Android dependency. */
enum class RingerMode { NORMAL, VIBRATE, SILENT }

/**
 * How an incoming call alerts the user. Pure decision, unit-tested; [RingtonePlayer] plays it.
 *
 * Rules (like the system dialer):
 *  - call waiting (a call is already up): only the short in-call waiting beep, which the
 *    user hears in the earpiece -- no ringtone, no vibration, whatever the ringer mode;
 *  - Do Not Disturb active: nothing, unless the user let our "Anrufe" channel override
 *    DND in the system settings (NotificationChannel.canBypassDnd). Door stations get no
 *    special DND bypass: the RingPolicy "Türklingel trotzdem" override only lifts the
 *    app's own "Klingeln aus", not the system DND;
 *  - ringer SILENT: nothing; VIBRATE: vibration only;
 *  - ringer NORMAL: ringtone, plus vibration if "Beim Klingeln vibrieren" is on.
 */
data class RingAlert(val sound: Boolean, val vibrate: Boolean, val waitingBeep: Boolean) {
    val isSilent: Boolean get() = !sound && !vibrate && !waitingBeep

    companion object {
        val NONE = RingAlert(sound = false, vibrate = false, waitingBeep = false)

        fun decide(
            ringerMode: RingerMode,
            dndActive: Boolean,
            channelBypassesDnd: Boolean,
            vibrateWhenRinging: Boolean,
            waiting: Boolean,
        ): RingAlert {
            if (waiting) return RingAlert(sound = false, vibrate = false, waitingBeep = true)
            if (dndActive && !channelBypassesDnd) return NONE
            return when (ringerMode) {
                RingerMode.SILENT -> NONE
                RingerMode.VIBRATE -> RingAlert(sound = false, vibrate = true, waitingBeep = false)
                RingerMode.NORMAL -> RingAlert(sound = true, vibrate = vibrateWhenRinging, waitingBeep = false)
            }
        }

        /** Ringing vibration: 1 s on, 1 s off, repeated from index 0. */
        val VIBRATION_PATTERN_MS = longArrayOf(0L, 1_000L, 1_000L)
    }
}
