package de.haphone.app.test.tailscale

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.system.OsConstants
import android.util.Log
import libtailscale.Libtailscale
import java.util.UUID

/**
 * The VPN libtailscale runs its WireGuard tunnel in. Split tunnel only ([TailnetRoutes]),
 * no DNS takeover, so everything except tailnet traffic keeps using the normal network.
 *
 * Started by [Tailscale.connect] (from the app process that also runs SipService). The
 * system keeps an established VPN service alive by itself, no own foreground notification.
 */
class TsVpnService : VpnService(), libtailscale.IPNService {
    private val id = UUID.randomUUID().toString()
    @Volatile private var closed = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_STOP -> {
                close()
                START_NOT_STICKY
            }
            else -> {
                // ACTION_START, Always-on VPN ("android.net.VpnService") or a restart after
                // the process was killed: hand ourselves to Go, it builds the tunnel.
                Tailscale.ensureStarted(this)
                Libtailscale.requestVPN(this)
                START_STICKY
            }
        }
    }

    override fun id(): String = id

    override fun protect(fd: Int): Boolean = goSafe("protect", false) { super.protect(fd) }

    // Go calls the IPNService methods below without an error result: they must not throw.
    override fun newBuilder(): libtailscale.VPNServiceBuilder = goSafe("newBuilder", null) { makeBuilder() }
        ?: SplitTunnelBuilder(Builder())

    private fun makeBuilder(): libtailscale.VPNServiceBuilder {
        val b = Builder()
            .setSession("HA-Phone")
            .allowFamily(OsConstants.AF_INET)
            .allowFamily(OsConstants.AF_INET6)
        // setMetered exists from Android 10. On 8/9 the NoSuchMethodError stayed pending in
        // this Go callback (NewBuilder has no error result) and the next JNI call aborted
        // the app with "Unknown reference: 42" (Mi 6, Android 9).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) b.setMetered(false)
        return SplitTunnelBuilder(b)
    }

    override fun updateVpnStatus(active: Boolean) = goSafe("updateVpnStatus", Unit) {
        Tailscale.onVpnActive(active)
    }

    override fun close() = goSafe("close", Unit) {
        if (closed) return@goSafe
        closed = true
        Libtailscale.serviceDisconnect(this)
        stopSelf()
    }

    override fun disconnectVPN() = goSafe("disconnectVPN", Unit) {
        stopSelf()
    }

    override fun onRevoke() {
        // Another VPN app took over (Android allows only one). Fall back to LAN.
        Log.w(TAG, "VPN revoked by the system / another VPN")
        Tailscale.onRevoked()
        close()
        super.onRevoke()
    }

    override fun onDestroy() {
        close()
        Tailscale.onVpnActive(false)
        super.onDestroy()
    }

    private class SplitTunnelBuilder(private val b: Builder) : libtailscale.VPNServiceBuilder {
        override fun setMTU(mtu: Int) {
            b.setMtu(mtu)
        }

        override fun addAddress(addr: String, prefix: Int) {
            b.addAddress(addr, prefix)
        }

        override fun addRoute(addr: String, prefix: Int) {
            if (TailnetRoutes.isAllowed(addr, prefix)) {
                b.addRoute(addr, prefix)
            } else {
                Log.d(TAG, "route dropped (split tunnel): $addr/$prefix")
            }
        }

        // Only narrow tailnet routes are added, so nothing needs excluding.
        override fun excludeRoute(addr: String, prefix: Int) = Unit

        // MagicDNS (100.100.100.100) never becomes the phone's DNS.
        override fun addDNSServer(server: String) = Unit
        override fun addSearchDomain(domain: String) = Unit

        override fun establish(): libtailscale.ParcelFileDescriptor? =
            b.establish()?.let { pfd -> libtailscale.ParcelFileDescriptor { pfd.detachFd() } }
    }

    companion object {
        private const val TAG = "TsVpnService"
        const val ACTION_START = "de.haphone.app.test.tailscale.START"
        const val ACTION_STOP = "de.haphone.app.test.tailscale.STOP"

        fun start(context: Context) {
            context.startService(Intent(context, TsVpnService::class.java).setAction(ACTION_START))
        }

        fun stop(context: Context) {
            context.startService(Intent(context, TsVpnService::class.java).setAction(ACTION_STOP))
        }
    }
}
