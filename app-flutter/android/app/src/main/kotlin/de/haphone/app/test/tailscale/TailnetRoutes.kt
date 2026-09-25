package de.haphone.app.test.tailscale

import java.net.Inet6Address
import java.net.InetAddress

/**
 * Split tunnel: only the tailnet itself goes through our VPN.
 *
 * libtailscale hands us every route of the netmap (exit-node default routes, subnet routes,
 * ...). We only let through what lies inside 100.64.0.0/10 (Tailscale IPv4) or
 * fd7a:115c:a1e0::/48 (Tailscale IPv6), so normal internet traffic of the phone never
 * enters the tunnel.
 */
object TailnetRoutes {
    private val V4_NET = byteArrayOf(100, 64, 0, 0)
    private const val V4_BITS = 10
    private val V6_NET = byteArrayOf(
        0xfd.toByte(), 0x7a, 0x11, 0x5c, 0xa1.toByte(), 0xe0.toByte(),
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    )
    private const val V6_BITS = 48

    fun isAllowed(address: String, prefixLength: Int): Boolean {
        val bytes = parse(address) ?: return false
        val (net, bits) = if (bytes.size == 4) V4_NET to V4_BITS else V6_NET to V6_BITS
        if (prefixLength < bits || prefixLength > bytes.size * 8) return false
        return samePrefix(bytes, net, bits)
    }

    /** Numeric literals only, never a DNS lookup. */
    private fun parse(address: String): ByteArray? {
        if (':' in address) {
            return try {
                (InetAddress.getByName(address) as? Inet6Address)?.address
            } catch (_: Exception) {
                null
            }
        }
        val parts = address.split('.')
        if (parts.size != 4) return null
        val out = ByteArray(4)
        for ((i, p) in parts.withIndex()) {
            val v = p.toIntOrNull() ?: return null
            if (v !in 0..255 || p.isEmpty() || p.length > 3) return null
            out[i] = v.toByte()
        }
        return out
    }

    private fun samePrefix(a: ByteArray, b: ByteArray, bits: Int): Boolean {
        for (i in 0 until bits) {
            val mask = 0x80 ushr (i % 8)
            if ((a[i / 8].toInt() and mask) != (b[i / 8].toInt() and mask)) return false
        }
        return true
    }
}
