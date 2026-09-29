package de.haphone.app.test.tailscale

/**
 * Which address the app uses for the PBX (SIP registrar and API).
 *
 * The direct LAN address whenever the box answers there ([lanDirect]: at home, or at
 * another site connected by a site-to-site VPN), checked by [TailnetManager] on every
 * network change and once a minute. Only when it does not answer and our tunnel runs,
 * the tailnet address. The route change re-registers SIP (see TailnetManager.updateRoute).
 */
object TailnetRoute {
    fun useTailnet(pbxTailnetIp: String?, tunnelRunning: Boolean, lanDirect: Boolean = false): Boolean =
        tunnelRunning && !pbxTailnetIp.isNullOrBlank() && !lanDirect

    fun sipHost(lanHost: String, pbxTailnetIp: String?, tunnelRunning: Boolean, lanDirect: Boolean = false): String =
        if (useTailnet(pbxTailnetIp, tunnelRunning, lanDirect)) pbxTailnetIp.orEmpty() else lanHost

    /** The PBX's tailnet transport has its own port (tailnet address in Contact/SDP). */
    fun sipPort(
        lanPort: String,
        tailnetPort: String?,
        pbxTailnetIp: String?,
        tunnelRunning: Boolean,
        lanDirect: Boolean = false,
    ): String =
        if (useTailnet(pbxTailnetIp, tunnelRunning, lanDirect) && !tailnetPort.isNullOrBlank()) tailnetPort else lanPort

    /** The PBX API listens on every interface (80 and 8443), so the tailnet host needs no port. */
    fun apiHost(lanApiHost: String, pbxTailnetIp: String?, tunnelRunning: Boolean, lanDirect: Boolean = false): String =
        if (useTailnet(pbxTailnetIp, tunnelRunning, lanDirect)) pbxTailnetIp.orEmpty() else lanApiHost
}

/**
 * Whether a periodic direct-route probe may flip [TailnetManager.lanDirect]: a single
 * slow TLS handshake over a site-to-site VPN must not move the SIP registration (the
 * re-register leaves a few seconds in which calls get lost). A differing probe only
 * counts when [confirmations] follow-up probes agree; after a real network change the
 * first probe decides (the old route is gone anyway).
 */
object LanProbeDecision {
    fun decide(current: Boolean, first: Boolean, confirm: () -> Boolean, confirmations: Int, networkChanged: Boolean): Boolean {
        if (first == current || networkChanged) return first
        repeat(confirmations) { if (confirm() != first) return current }
        return first
    }
}
