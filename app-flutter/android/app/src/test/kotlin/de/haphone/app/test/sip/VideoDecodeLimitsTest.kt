package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoDecodeLimitsTest {
    @Test
    fun `decode buffer fits a 720p I420 frame from the door station`() {
        val i420_720p = 1280L * 720 * 3 / 2
        val i420_vga = 640L * 480 * 3 / 2
        assertTrue(VideoDecodeLimits.decodedBufferBytes() >= i420_720p)
        // The old default (352x288) was too small for 640x480: the bug this fixes.
        assertTrue(VideoDecodeLimits.decodedBufferBytes(352, 288) < i420_vga)
    }

    @Test
    fun `advertises constrained baseline level 3_1 with FU-A`() {
        assertEquals(mapOf("profile-level-id" to "42e01f", "packetization-mode" to "1"), VideoDecodeLimits.h264Fmtp.toMap())
    }
}
