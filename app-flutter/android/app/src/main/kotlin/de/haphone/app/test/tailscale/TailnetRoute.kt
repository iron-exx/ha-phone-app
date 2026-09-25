package de.haphone.app.test.tailscale

/**
 * Which address the app uses for the PBX (SIP registrar and HTTP API).
 *
 * While our tunnel runs, always the tailnet address, at home too: Tailscale connects
 * directly on the LAN, and the registration survives Wi-Fi <-> mobile switches because
 * the phone's own 100.x address never changes. Otherwise the LAN address from pairing.
 */
object TailnetRoute {
    fun useTailnet(pbxTailnetIp: String?, tunnelRunning: Boolean): Boolean =
        tunnelRunning && !pbxTailnetIp.isNullOrBlank()

    fun sipHost(lanHost: String, pbxTailnetIp: String?, tunnelRunning: Boolean): String =
        if (useTailnet(pbxTailnetIp, tunnelRunning)) pbxTailnetIp.orEmpty() else lanHost

    /** The PBX's tailnet transport has its own port (tailnet address in Contact/SDP). */
    fun sipPort(lanPort: String, tailnetPort: String?, pbxTailnetIp: String?, tunnelRunning: Boolean): String =
        if (useTailnet(pbxTailnetIp, tunnelRunning) && !tailnetPort.isNullOrBlank()) tailnetPort else lanPort

    /** The PBX web API listens on port 80 on every interface, so the tailnet host needs no port. */
    fun apiHost(lanApiHost: String, pbxTailnetIp: String?, tunnelRunning: Boolean): String =
        if (useTailnet(pbxTailnetIp, tunnelRunning)) pbxTailnetIp.orEmpty() else lanApiHost
}
