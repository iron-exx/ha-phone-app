package de.haphone.app.test.net

import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.Base64
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.X509TrustManager

/**
 * Pinned TLS to the PBX (HA-Phone 0.7.130+).
 *
 * The box has one self-signed cert for SIP TLS (5061) and the HTTPS mobile API (8443).
 * Its SHA-256 comes out of band with the pairing QR code (or once from /api/mobile/config
 * for devices paired before). With a pin every API call goes to https://host:8443 and only
 * that exact cert is accepted; host names are not checked, the box is reached by LAN IP and
 * tailnet IP alike. Without a pin (older PBX) it stays plain http like before.
 */
object PbxTls {
    data class Pin(val sha256: String, val httpsPort: Int) {
        val normalized: String get() = normalize(sha256)
        val isSet: Boolean get() = httpsPort > 0 && normalized.length == 64 && normalized.all { it in HEX }

        companion object {
            val NONE = Pin("", 0)
        }
    }

    /** Pin of the current pairing; set from SecurePrefs at start and on (re)pairing. */
    @Volatile var current: Pin = Pin.NONE
        private set

    @Volatile private var factory: Pair<String, SSLSocketFactory>? = null

    fun configure(pin: Pin) {
        current = if (pin.isSet) pin else Pin.NONE
    }

    fun baseUrl(apiHost: String, pin: Pin = current): String =
        if (pin.isSet) "https://${bracketed(hostOnly(apiHost))}:${pin.httpsPort}" else "http://$apiHost"

    /** Opens `<base><path>`; HTTPS connections accept only the pinned cert. */
    fun open(apiHost: String, path: String, pin: Pin = current): HttpURLConnection {
        val conn = URL(baseUrl(apiHost, pin) + path).openConnection() as HttpURLConnection
        if (conn is HttpsURLConnection && pin.isSet) {
            conn.sslSocketFactory = socketFactory(pin)
            // The pin identifies the box; its IP changes between LAN and tailnet.
            conn.hostnameVerifier = javax.net.ssl.HostnameVerifier { _, _ -> true }
        }
        return conn
    }

    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    fun matches(der: ByteArray, pin: String): Boolean {
        val want = normalize(pin)
        return want.isNotEmpty() && MessageDigest.isEqual(sha256Hex(der).toByteArray(), want.toByteArray())
    }

    /** DER bytes of the first certificate in a PEM text (PJSIP hands out PEM). */
    fun pemToDer(pem: String): ByteArray? {
        val begin = pem.indexOf(PEM_BEGIN).takeIf { it >= 0 } ?: return null
        val end = pem.indexOf(PEM_END, begin).takeIf { it > begin } ?: return null
        val b64 = pem.substring(begin + PEM_BEGIN.length, end).filterNot { it.isWhitespace() }
        return runCatching { Base64.getDecoder().decode(b64) }.getOrNull()
    }

    /**
     * SIP TLS: may this connection carry our REGISTER? True without a pin (older pairing)
     * and for non-TLS transports; with a pin only for exactly the paired cert.
     */
    fun acceptSipTls(pin: Pin, isTls: Boolean, remoteCertPem: String?): Boolean {
        if (!pin.isSet || !isTls) return true
        val der = remoteCertPem?.let(::pemToDer) ?: return false
        return matches(der, pin.normalized)
    }

    /** Last time a SIP TLS connection was dropped for a wrong cert (0 = never), for Diagnose. */
    @Volatile var lastSipPinMismatchMs: Long = 0L

    private fun socketFactory(pin: Pin): SSLSocketFactory {
        factory?.let { (fp, f) -> if (fp == pin.normalized) return f }
        val ctx = SSLContext.getInstance("TLS")
        ctx.init(null, arrayOf(PinningTrustManager(pin.normalized)), null)
        return ctx.socketFactory.also { factory = pin.normalized to it }
    }

    private class PinningTrustManager(private val pin: String) : X509TrustManager {
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            val leaf = chain?.firstOrNull() ?: throw CertificateException("no server certificate")
            if (!matches(leaf.encoded, pin)) throw CertificateException("PBX certificate does not match the paired fingerprint")
        }

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) =
            throw CertificateException("client certificates not supported")

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    private fun normalize(fp: String) = fp.replace(":", "").trim().lowercase()

    /** "1.2.3.4:80" -> "1.2.3.4", "[fd7a::1]:80" -> "fd7a::1", "fd7a::1" stays. */
    internal fun hostOnly(apiHost: String): String {
        val h = apiHost.trim()
        if (h.startsWith("[")) return h.substringAfter("[").substringBefore("]")
        return if (h.count { it == ':' } == 1) h.substringBefore(":") else h
    }

    private fun bracketed(host: String) = if (host.contains(':')) "[$host]" else host

    private const val HEX = "0123456789abcdef"
    private const val PEM_BEGIN = "-----BEGIN CERTIFICATE-----"
    private const val PEM_END = "-----END CERTIFICATE-----"
}
