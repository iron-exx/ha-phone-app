package de.haphone.app.test.sip

/**
 * The PBX's STUN server (HA-Phone 0.7.115+, 3478/udp) for the account's SIP domain.
 * Used for media only: behind NAT the SDP then carries the address the PBX can reach.
 * Without it the door station's early-media video went to the phone's private address
 * and the preview stayed black, because the app sends no RTP before answering.
 */
object StunServer {
    const val PORT = 3478

    /** "192.168.7.10:5061" -> "192.168.7.10:3478", "[fd00::1]:5061" -> "[fd00::1]:3478", null if empty. */
    fun forDomain(domain: String): String? {
        val trimmed = domain.trim()
        if (trimmed.isEmpty()) return null
        val host = when {
            trimmed.startsWith("[") -> trimmed.substringBefore("]") + "]"
            trimmed.count { it == ':' } == 1 -> trimmed.substringBefore(":")
            trimmed.contains(':') -> "[$trimmed]"
            else -> trimmed
        }
        return if (host.isEmpty() || host == "[]") null else "$host:$PORT"
    }
}
