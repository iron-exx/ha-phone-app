package de.haphone.app.test.calls

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RingAlertTest {
    private fun decide(
        mode: RingerMode = RingerMode.NORMAL,
        dnd: Boolean = false,
        bypass: Boolean = false,
        vibrateWhenRinging: Boolean = true,
        waiting: Boolean = false,
    ) = RingAlert.decide(mode, dnd, bypass, vibrateWhenRinging, waiting)

    @Test
    fun `normal ringer plays ringtone and vibrates`() {
        assertEquals(RingAlert(sound = true, vibrate = true, waitingBeep = false), decide())
    }

    @Test
    fun `normal ringer without vibrate-when-ringing only plays the ringtone`() {
        assertEquals(RingAlert(sound = true, vibrate = false, waitingBeep = false), decide(vibrateWhenRinging = false))
    }

    @Test
    fun `vibrate ringer only vibrates`() {
        assertEquals(RingAlert(sound = false, vibrate = true, waitingBeep = false), decide(RingerMode.VIBRATE))
        assertEquals(RingAlert(sound = false, vibrate = true, waitingBeep = false), decide(RingerMode.VIBRATE, vibrateWhenRinging = false))
    }

    @Test
    fun `silent ringer is completely silent`() {
        assertTrue(decide(RingerMode.SILENT).isSilent)
    }

    @Test
    fun `do not disturb silences the call unless the channel may bypass it`() {
        assertTrue(decide(dnd = true).isSilent)
        assertEquals(RingAlert(sound = true, vibrate = true, waitingBeep = false), decide(dnd = true, bypass = true))
        assertTrue(decide(RingerMode.SILENT, dnd = true, bypass = true).isSilent)
    }

    @Test
    fun `call waiting only beeps, whatever the ringer mode`() {
        val beep = RingAlert(sound = false, vibrate = false, waitingBeep = true)
        assertEquals(beep, decide(waiting = true))
        assertEquals(beep, decide(RingerMode.SILENT, waiting = true))
        assertEquals(beep, decide(dnd = true, waiting = true))
    }

    @Test
    fun `vibration pattern repeats on and off`() {
        assertEquals(listOf(0L, 1_000L, 1_000L), RingAlert.VIBRATION_PATTERN_MS.toList())
    }
}
