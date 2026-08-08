package de.haphone.app.test.sip

/**
 * Codec priority contract for CALL-01/D-07 -- all 3 codecs named in
 * CALL-01 (Opus, G.722, G.711 as pcma/pcmu) verified for real against
 * the HA-Phone box. Order matters: highest priority first. Kept as a
 * pure data list (no PJSUA2 dependency) so it is unit-testable without
 * the native library -- PjsuaEndpointHolder applies these via
 * [CodecPriorityApplier] in a real Endpoint.
 */
object CodecPriorities {
    val ordered: List<Pair<String, Int>> = listOf(
        "opus/48000" to 255,
        "g722/16000" to 200,
        "pcma/8000" to 150,
        "pcmu/8000" to 150,
    )
}

/** Seam wrapping PJSUA2 Endpoint.codecSetPriority so codec application is unit-testable. */
interface CodecPriorityApplier {
    fun setPriority(codecId: String, priority: Int)
}
