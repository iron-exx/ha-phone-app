package de.haphone.app.test.tailscale

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import libtailscale.Libtailscale
import java.net.Inet4Address

/**
 * Tells libtailscale which physical network is the default (interface name, gateway,
 * DNS servers). Without it Go sees no default route ("Rebind; defIf=\"\""), treats the
 * phone as offline and never reconnects the stored identity after a restart.
 *
 * Only non-VPN networks count, our own tunnel must never become its own underlay.
 */
object TsNetworkMonitor {
    private const val TAG = "TsNetworkMonitor"

    private val networks = LinkedHashMap<Network, Pair<NetworkCapabilities?, LinkProperties?>>()
    @Volatile private var started = false
    @Volatile private var lastIface: String? = null

    /** "dns1 dns2\nsearch.domain", the format Go parses in getPlatformDNSConfig. */
    @Volatile var platformDnsConfig: String = ""
        private set

    @Synchronized
    fun start(context: Context) {
        if (started) return
        started = true
        val cm = context.applicationContext.getSystemService(ConnectivityManager::class.java)
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = update { networks.getOrPut(network) { null to null } }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                update { networks[network] = caps to networks[network]?.second }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) =
                update { networks[network] = networks[network]?.first to lp }

            override fun onLost(network: Network) = update { networks.remove(network) }
        })
    }

    private fun update(change: () -> Unit) {
        val (iface, gateway, dns) = synchronized(this) {
            change()
            val best = networks.entries
                .filter { it.value.second != null }
                .sortedByDescending { it.value.first?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true }
                .firstOrNull()
            val lp = best?.value?.second
            val gw = lp?.routes
                ?.filter { it.isDefaultRoute && it.gateway != null }
                ?.sortedBy { if (it.gateway is Inet4Address) 0 else 1 }
                ?.firstNotNullOfOrNull { it.gateway?.hostAddress }
                .orEmpty()
            val dnsLine = lp?.dnsServers?.joinToString(" ") { it.hostAddress.orEmpty() }.orEmpty()
            val dnsText = if (lp?.domains.isNullOrBlank()) dnsLine else "$dnsLine\n${lp?.domains}"
            Triple(lp?.interfaceName.orEmpty(), gw, dnsText)
        }
        platformDnsConfig = dns
        if (iface == lastIface) return
        lastIface = iface
        Log.i(TAG, "default network: iface=${iface.ifEmpty { "none" }} gw=$gateway")
        Libtailscale.onGatewayChanged(gateway)
        Libtailscale.onDNSConfigChanged(iface)
    }
}
