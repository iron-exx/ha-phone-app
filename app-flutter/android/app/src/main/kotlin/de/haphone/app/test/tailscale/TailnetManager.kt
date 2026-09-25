package de.haphone.app.test.tailscale

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import de.haphone.app.test.HAPhoneTestApplication
import de.haphone.app.test.SecurePrefs
import org.json.JSONObject
import java.net.HttpURLConnection
import java.util.concurrent.Executors

/**
 * "Unterwegs erreichbar": joins the tailnet the PBX handed out at QR pairing and switches
 * SIP and the API to the PBX's tailnet address while the tunnel runs.
 *
 * Pairing stores the `tailscale` block ([configure]). [start] then asks for the VPN
 * consent once ([TsConsentActivity]) and joins: with an auth key silently, otherwise via
 * Tailscale's login page in the browser. After every process start [resume] brings the
 * tunnel back without any UI, as long as the consent still holds.
 */
object TailnetManager {
    private const val TAG = "TailnetManager"

    private const val K_CONFIGURED = "ts_configured"
    private const val K_LOGIN = "ts_login"
    private const val K_AUTH_KEY = "ts_auth_key"
    private const val K_HOSTNAME = "ts_hostname"
    private const val K_PBX_IP = "ts_pbx_ip"
    private const val K_REPORTED = "ts_reported_node"
    private const val K_SIP_PORT = "ts_sip_port"
    // ipn.State enum order (tailscale.com/ipn).
    private val STATE_NAMES = listOf(
        "NoState", "InUseOtherUser", "NeedsLogin", "NeedsMachineAuth", "Stopped", "Starting", "Running",
    )
    private const val SETTLE_TRIES = 20
    private const val SETTLE_STEP_MS = 250L

    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "tailnet") }
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var watcher: libtailscale.NotificationManager? = null
    @Volatile var backendState: Int = -1
        private set
    @Volatile var lastLoginUrl: String? = null
        private set
    @Volatile var lastError: String? = null
        private set
    @Volatile private var routedViaTailnet = false

    /** Tunnel up and logged in: the PBX is reached over 100.x. */
    val running: Boolean
        get() = Tailscale.vpnActive && backendState == Tailscale.STATE_RUNNING

    fun isConfigured(context: Context): Boolean =
        SecurePrefs.read(context) { it.getBoolean(K_CONFIGURED, false) }

    fun pbxTailnetIp(context: Context): String? =
        SecurePrefs.read(context) { it.getString(K_PBX_IP, null) }

    /** Null for a PBX older than 0.7.125 (no own tailnet transport): keep the LAN port. */
    fun tailnetSipPort(context: Context): String? =
        SecurePrefs.read(context) { it.getString(K_SIP_PORT, null) }

    /** Stores the `tailscale` block of /provision/complete (null = PBX has no Tailscale). */
    fun configure(context: Context, block: Map<*, *>?) {
        val edit = SecurePrefs.get(context).edit()
        if (block == null || block["pbx_tailnet_ip"] == null) {
            edit.putBoolean(K_CONFIGURED, false).remove(K_AUTH_KEY).remove(K_PBX_IP).commit()
            return
        }
        edit.putBoolean(K_CONFIGURED, true)
            .putString(K_LOGIN, block["login"] as? String ?: "interactive")
            .putString(K_HOSTNAME, block["hostname"] as? String ?: "haphone")
            .putString(K_PBX_IP, block["pbx_tailnet_ip"] as String)
            .putString(K_SIP_PORT, (block["sip_port_tailnet"] as? Number)?.toInt()?.toString())
            .remove(K_REPORTED)
        val key = block["auth_key"] as? String
        if (!key.isNullOrBlank()) edit.putString(K_AUTH_KEY, key) else edit.remove(K_AUTH_KEY)
        edit.commit()
    }

    /**
     * Joins / reconnects. Returns "consent" when the system VPN dialog was opened first
     * (joining continues from [TsConsentActivity]), "started" otherwise, "off" when not set up.
     */
    fun start(context: Context): String {
        val app = context.applicationContext
        if (!isConfigured(app)) return "off"
        if (Tailscale.consentIntent(app) != null) {
            app.startActivity(Intent(app, TsConsentActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return "consent"
        }
        worker.execute { join(app) }
        return "started"
    }

    /** Process start: reconnect silently if paired with Tailscale and the consent still holds. */
    fun resume(context: Context) {
        val app = context.applicationContext
        if (!isConfigured(app) || Tailscale.consentIntent(app) != null) return
        worker.execute { join(app) }
    }

    internal fun onConsentResult(context: Context, granted: Boolean) {
        if (granted) {
            worker.execute { join(context.applicationContext) }
        } else {
            lastError = "VPN-Erlaubnis abgelehnt"
            Log.w(TAG, "VPN consent denied")
        }
    }

    private fun join(app: Context) {
        try {
            ensureWatching(app)
            lastError = null
            val prefs = SecurePrefs.get(app)
            val hostname = prefs.getString(K_HOSTNAME, null) ?: "haphone"
            val key = prefs.getString(K_AUTH_KEY, null)
            // Right after process start the backend still says NoState while it loads the
            // stored identity. Deciding on that would force a new login on every restart.
            val state = settledState(app)
            Log.i(TAG, "join: state=$state key=${!key.isNullOrBlank()}")
            val up = state == "Running" || state == "Starting"
            when {
                // Fresh pairing key: use it whenever the tunnel is not already up.
                !key.isNullOrBlank() && !up -> {
                    Tailscale.loginWithAuthKey(app, key, hostname)
                    // One-time key: gone once used, never kept around.
                    prefs.edit().remove(K_AUTH_KEY).commit()
                }
                key.isNullOrBlank() && state == "NeedsLogin" -> Tailscale.startInteractiveLogin(app, hostname)
                else -> {
                    if (!key.isNullOrBlank()) prefs.edit().remove(K_AUTH_KEY).commit()
                    Tailscale.connect(app)
                }
            }
        } catch (e: Exception) {
            lastError = e.message
            Log.e(TAG, "join failed", e)
        }
    }

    /** Backend state once it left NoState (at most ~5 s), as ipn.State name. */
    private fun settledState(app: Context): String {
        repeat(SETTLE_TRIES) {
            val st = Tailscale.status(app).optString("BackendState")
            if (st.isNotEmpty() && st != "NoState") return st
            Thread.sleep(SETTLE_STEP_MS)
        }
        return Tailscale.status(app).optString("BackendState")
    }

    private fun ensureWatching(app: Context) {
        if (watcher != null) return
        Tailscale.onVpnChanged = { updateRoute(app) }
        watcher = Tailscale.watch(
            app,
            // Notifications can arrive out of order (a stale NoState after Running), so they
            // only trigger a re-read of the authoritative state.
            onState = { worker.execute { refreshState(app) } },
            onLoginUrl = { url ->
                lastLoginUrl = url
                openBrowser(app, url)
            },
        )
    }

    private fun refreshState(app: Context) {
        val name = runCatching { Tailscale.status(app).optString("BackendState") }.getOrDefault("")
        val st = STATE_NAMES.indexOf(name)
        if (st < 0) return
        val wasRunning = backendState == Tailscale.STATE_RUNNING
        backendState = st
        if (st == Tailscale.STATE_RUNNING && !wasRunning) {
            lastLoginUrl = null
            reportNode(app)
        }
        updateRoute(app)
    }

    private fun openBrowser(app: Context, url: String) {
        runCatching {
            app.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.onFailure { Log.w(TAG, "no browser for login URL", it) }
    }

    /** Re-registers SIP when the route to the PBX changes (tunnel up/down). */
    @Synchronized
    private fun updateRoute(app: Context) {
        val now = TailnetRoute.useTailnet(pbxTailnetIp(app), running)
        if (now == routedViaTailnet) return
        routedViaTailnet = now
        Log.i(TAG, "PBX route -> ${if (now) "tailnet" else "LAN"} (state=$backendState vpn=${Tailscale.vpnActive})")
        main.post {
            val a = app as? HAPhoneTestApplication ?: return@post
            if (!a.hasValidCredentials()) return@post
            a.refreshSipCredentials()
            runCatching { a.sipCallController.register() }
                .onFailure { Log.w(TAG, "re-register after route change failed", it) }
        }
    }

    /** Tells the PBX our node, so unpairing can remove the phone from the tailnet. */
    private fun reportNode(app: Context) {
        try {
            val self = Tailscale.status(app).optJSONObject("Self") ?: return
            val nodeId = self.optString("ID")
            val ip = self.optJSONArray("TailscaleIPs")?.let { arr ->
                (0 until arr.length()).map { arr.getString(it) }.firstOrNull { ':' !in it }
            }.orEmpty()
            if (nodeId.isBlank()) return
            val prefs = SecurePrefs.get(app)
            if (prefs.getString(K_REPORTED, null) == "$nodeId/$ip") return
            val auth = (app as HAPhoneTestApplication).getDeviceAuth()
            val host = auth["apiHost"].orEmpty()
            if (host.isBlank() || auth["deviceToken"].isNullOrBlank()) return
            val conn = de.haphone.app.test.net.PbxTls.open(host, "/api/mobile/device/tailscale")
            conn.requestMethod = "POST"
            conn.connectTimeout = 5_000
            conn.readTimeout = 10_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            val body = JSONObject()
                .put("device_id", auth["deviceId"].orEmpty().toIntOrNull() ?: 0)
                .put("device_token", auth["deviceToken"])
                .put("node_id", nodeId)
                .put("ip", ip)
            conn.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = conn.responseCode
            conn.disconnect()
            if (code in 200..299) {
                prefs.edit().putString(K_REPORTED, "$nodeId/$ip").apply()
                Log.i(TAG, "node $nodeId ($ip) reported to PBX")
            } else {
                Log.w(TAG, "node report -> HTTP $code")
            }
        } catch (e: Exception) {
            Log.w(TAG, "node report failed", e)
        }
    }

    /** For the reachability screen. */
    fun status(context: Context): Map<String, Any?> {
        val app = context.applicationContext
        val configured = isConfigured(app)
        var selfIp: String? = null
        var direct: Boolean? = null
        if (configured && backendState == Tailscale.STATE_RUNNING) {
            runCatching {
                val st = Tailscale.status(app)
                selfIp = st.optJSONObject("Self")?.optJSONArray("TailscaleIPs")?.optString(0)
                val pbx = pbxTailnetIp(app)
                st.optJSONObject("Peer")?.let { peers ->
                    for (k in peers.keys()) {
                        val p = peers.getJSONObject(k)
                        val ips = p.optJSONArray("TailscaleIPs")?.toString().orEmpty()
                        if (pbx != null && ips.contains("\"$pbx\"")) direct = p.optString("CurAddr").isNotEmpty()
                    }
                }
            }
        }
        return mapOf(
            "configured" to configured,
            "consentNeeded" to (configured && Tailscale.consentIntent(app) != null),
            "state" to backendState,
            "running" to running,
            "vpnActive" to Tailscale.vpnActive,
            "revoked" to Tailscale.revoked,
            "selfIp" to selfIp,
            "pbxIp" to pbxTailnetIp(app),
            "direct" to direct,
            "loginUrl" to lastLoginUrl,
            "error" to lastError,
        )
    }

    /** Unpairing: leave the tailnet and forget everything. */
    fun reset(context: Context) {
        val app = context.applicationContext
        runCatching { if (isConfigured(app)) Tailscale.logout(app) }
        SecurePrefs.get(app).edit()
            .remove(K_CONFIGURED).remove(K_LOGIN).remove(K_AUTH_KEY)
            .remove(K_HOSTNAME).remove(K_PBX_IP).remove(K_REPORTED).remove(K_SIP_PORT).commit()
        backendState = -1
        lastLoginUrl = null
        updateRoute(app)
    }
}
