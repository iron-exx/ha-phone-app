package de.haphone.app.test.tailscale

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Log
import de.haphone.app.test.SecurePrefs
import org.json.JSONArray
import org.json.JSONObject
import java.net.NetworkInterface
import java.util.Collections

/**
 * The Android side libtailscale calls back into (logging, encrypted state, device info).
 *
 * Tailscale's machine and node keys land in [SecurePrefs] (Android Keystore, AES-GCM) under
 * the "statestore-" prefix, next to the SIP credentials. Everything the official app offers
 * beyond that (MDM policies, hardware attestation, Taildrop, user CA certs) is switched off.
 */
class TsAppContext(context: Context) : libtailscale.AppContext {
    private val app = context.applicationContext

    override fun log(tag: String, line: String) = goSafe("log", Unit) {
        Log.d("TS/$tag", line)
        Unit
    }

    override fun encryptToPref(key: String, value: String) {
        SecurePrefs.get(app).edit().putString(key, value).commit()
    }

    override fun decryptFromPref(key: String): String =
        SecurePrefs.read(app) { it.getString(key, null) } ?: ""

    override fun getStateStoreKeysJSON(): String = goSafe("getStateStoreKeysJSON", "[]") {
        val keys = SecurePrefs.read(app) { prefs ->
            prefs.all.keys.filter { it.startsWith(STATE_PREFIX) }.map { it.removePrefix(STATE_PREFIX) }
        }
        JSONArray(keys).toString()
    }

    override fun getOSVersion(): String = Build.VERSION.RELEASE

    override fun getSDKInt(): Long = Build.VERSION.SDK_INT.toLong()

    override fun getDeviceName(): String =
        Settings.Global.getString(app.contentResolver, Settings.Global.DEVICE_NAME)
            ?: "${Build.MANUFACTURER} ${Build.MODEL}"

    override fun getInstallSource(): String = "haphone"

    override fun shouldUseGoogleDNSFallback(): Boolean = true

    override fun isChromeOS(): Boolean = false

    // Never upload diagnostics to Tailscale's log server.
    override fun isClientLoggingEnabled(): Boolean = false

    override fun getInterfacesAsJson(): String {
        val out = JSONArray()
        for (nif in Collections.list(NetworkInterface.getNetworkInterfaces())) {
            try {
                val addrs = JSONArray()
                for (ia in nif.interfaceAddresses) {
                    val host = ia.address?.hostAddress ?: continue
                    addrs.put(JSONObject().put("ip", host).put("prefixLen", ia.networkPrefixLength.toInt()))
                }
                out.put(
                    JSONObject()
                        .put("name", nif.name)
                        .put("index", nif.index)
                        .put("mtu", nif.mtu)
                        .put("up", nif.isUp)
                        .put("broadcast", nif.supportsMulticast())
                        .put("loopback", nif.isLoopback)
                        .put("pointToPoint", nif.isPointToPoint)
                        .put("multicast", nif.supportsMulticast())
                        .put("addrs", addrs),
                )
            } catch (_: Exception) {
                continue
            }
        }
        return out.toString()
    }

    // DNS of the physical default network (Go's own resolver for control/DERP). We never
    // make the tailnet the system DNS (CorpDNS off).
    override fun getPlatformDNSConfig(): String = goSafe("getPlatformDNSConfig", "") { TsNetworkMonitor.platformDnsConfig }

    // No MDM. The message must match syspolicy.ErrNoSuchKey, Go compares the text.
    override fun getSyspolicyStringValue(key: String): String = throw NoSuchKey()
    override fun getSyspolicyBooleanValue(key: String): Boolean = throw NoSuchKey()
    override fun getSyspolicyStringArrayJSONValue(key: String): String = throw NoSuchKey()

    override fun hardwareAttestationKeySupported(): Boolean = false
    override fun hardwareAttestationKeyCreate(): String = throw UnsupportedOperationException()
    override fun hardwareAttestationKeyRelease(id: String) = throw UnsupportedOperationException()
    override fun hardwareAttestationKeyPublic(id: String): ByteArray = throw UnsupportedOperationException()
    override fun hardwareAttestationKeySign(id: String, data: ByteArray): ByteArray =
        throw UnsupportedOperationException()
    override fun hardwareAttestationKeyLoad(id: String) = throw UnsupportedOperationException()

    // false = leave the socket on the default network (Go treats it as a no-op).
    override fun bindSocketToNetwork(fd: Int): Boolean = false

    override fun getUserCACertsPEM(): ByteArray = ByteArray(0)

    private class NoSuchKey : Exception("no such key")

    companion object {
        const val STATE_PREFIX = "statestore-"
    }
}
