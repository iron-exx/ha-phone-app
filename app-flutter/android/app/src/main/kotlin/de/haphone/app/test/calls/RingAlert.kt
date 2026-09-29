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
 *  - ringer NORMAL: ringtone, plus vibration if "Beim Klingeln vibrieren" is on;
 *  - "Türklingel auch bei lautlos" ([loudDoor], a door station calls): rings like an alarm
 *    clock would -- ringtone on the alarm stream plus vibration despite a silent/vibrate
 *    ringer and through DND while DND lets alarms through (not in "total silence").
 */
data class RingAlert(
    val sound: Boolean,
    val vibrate: Boolean,
    val waitingBeep: Boolean,
    /** Play on the alarm stream (USAGE_ALARM), which the ringer mode does not mute. */
    val alarmStream: Boolean = false,
) {
    val isSilent: Boolean get() = !sound && !vibrate && !waitingBeep

    companion object {
        val NONE = RingAlert(sound = false, vibrate = false, waitingBeep = false)
        val LOUD_DOOR = RingAlert(sound = true, vibrate = true, waitingBeep = false, alarmStream = true)

        fun decide(
            ringerMode: RingerMode,
            dndActive: Boolean,
            channelBypassesDnd: Boolean,
            vibrateWhenRinging: Boolean,
            waiting: Boolean,
            loudDoor: Boolean = false,
            alarmsAllowed: Boolean = true,
        ): RingAlert {
            if (waiting) return RingAlert(sound = false, vibrate = false, waitingBeep = true)
            val dndBlocks = dndActive && !channelBypassesDnd
            if (loudDoor && (dndBlocks || ringerMode != RingerMode.NORMAL)) {
                return if (alarmsAllowed) LOUD_DOOR else NONE
            }
            if (dndBlocks) return NONE
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
