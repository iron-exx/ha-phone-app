package de.haphone.app.test.sip

/** Largest door-station picture the app decodes, and the H.264 fmtp it advertises for it. */
object VideoDecodeLimits {
    const val MAX_WIDTH = 1920
    const val MAX_HEIGHT = 1080

    /** Constrained Baseline, level 3.1 (up to 720p30), FU-A packetization like the Akuvox. */
    val h264Fmtp: List<Pair<String, String>> = listOf(
        "profile-level-id" to "42e01f",
        "packetization-mode" to "1",
    )

    /** Bytes PJSIP reserves for one decoded frame (vid_stream: w * h * 4). */
    fun decodedBufferBytes(width: Int = MAX_WIDTH, height: Int = MAX_HEIGHT): Long = width.toLong() * height * 4
}
