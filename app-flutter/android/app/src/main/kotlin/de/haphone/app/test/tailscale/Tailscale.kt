package de.haphone.app.test.tailscale

import android.content.Context
import android.net.VpnService
import android.util.Log
import de.haphone.app.test.SecurePrefs
import libtailscale.Libtailscale
import org.json.JSONObject

/**
 * Thin facade over the embedded libtailscale (one Go backend per process).
 *
 * All LocalAPI calls block (up to [TIMEOUT_MS]); never call them on the main thread.
 */
object Tailscale {
    private const val TAG = "Tailscale"
    private const val TIMEOUT_MS = 30_000

    // ipn.NotifyWatchOpt bits and ipn.State names (tailscale.com/ipn).
    private const val NOTIFY_INITIAL_STATE = 2L
    private const val NOTIFY_NO_NETMAP = 8192L
    // ipn.State: Notify.State is the numeric enum.
    const val STATE_NEEDS_LOGIN = 2
    const val STATE_RUNNING = 6

    @Volatile private var app: libtailscale.Application? = null

    /** True while our VPN is established (set by [TsVpnService]). */
    @Volatile var vpnActive: Boolean = false
        private set

    /** True after Android handed the VPN to another app; cleared on the next [connect]. */
    @Volatile var revoked: Boolean = false
        private set

    @Synchronized
    fun ensureStarted(context: Context): libtailscale.Application {
        app?.let { return it }
        val ctx = context.applicationContext
        // directFileRoot "" = Taildrop off; hardware attestation off.
        return Libtailscale.start(ctx.filesDir.absolutePath, "", false, TsAppContext(ctx))
            .also { app = it }
    }

    /** Null when the VPN may be started right away, else the system consent intent. */
    fun consentIntent(context: Context) = VpnService.prepare(context)

    /**
     * Joins the tailnet with a one-time auth key and brings the tunnel up.
     * Split tunnel, no MagicDNS as system DNS, no subnet routes, no exit node.
     */
    fun loginWithAuthKey(context: Context, authKey: String, hostname: String, controlUrl: String? = null) {
        val a = ensureStarted(context)
        val prefs = JSONObject()
            .put("WantRunning", true)
            .put("CorpDNS", false)
            .put("RouteAll", false)
            .put("Hostname", hostname)
        if (!controlUrl.isNullOrBlank()) prefs.put("ControlURL", controlUrl)
        val body = JSONObject().put("AuthKey", authKey).put("UpdatePrefs", prefs)
        call(a, "POST", "start", body.toString())
        connect(context)
    }

    /**
     * Browser login (no auth key): [onUrl] receives the login URL the user opens and signs in
     * with (e.g. GitHub). The tunnel comes up once the login is done; [onRunning] then fires.
     */
    fun loginInteractive(
        context: Context,
        hostname: String,
        onUrl: (String) -> Unit,
        onRunning: () -> Unit = {},
    ) {
        val a = ensureStarted(context)
        val prefs = JSONObject()
            .put("WantRunning", true)
            .put("CorpDNS", false)
            .put("RouteAll", false)
            .put("Hostname", hostname)
        call(a, "POST", "start", JSONObject().put("UpdatePrefs", prefs).toString())
        var watcher: libtailscale.NotificationManager? = null
        watcher = a.watchNotifications(NOTIFY_INITIAL_STATE or NOTIFY_NO_NETMAP) { bytes ->
            val n = JSONObject(bytes.decodeToString())
            n.optString("BrowseToURL").takeIf { it.isNotEmpty() }?.let(onUrl)
            if (n.has("State") && n.optInt("State") == STATE_RUNNING) {
                onRunning()
                watcher?.stop()
            }
        }
        call(a, "POST", "login-interactive", null)
        connect(context)
    }

    /** (Re)starts the tunnel with the stored identity. */
    fun connect(context: Context) {
        revoked = false
        val a = ensureStarted(context)
        call(a, "PATCH", "prefs", """{"WantRunning":true,"WantRunningSet":true}""")
        TsVpnService.start(context)
    }

    fun disconnect(context: Context) {
        app?.let { call(it, "PATCH", "prefs", """{"WantRunning":false,"WantRunningSet":true}""") }
        TsVpnService.stop(context)
    }

    /** Leaves the tailnet and forgets the node identity (unpairing). */
    fun logout(context: Context) {
        app?.let { runCatching { call(it, "POST", "logout", null) } }
        TsVpnService.stop(context)
        val prefs = SecurePrefs.get(context)
        val edit = prefs.edit()
        prefs.all.keys.filter { it.startsWith(TsAppContext.STATE_PREFIX) }.forEach { edit.remove(it) }
        edit.commit()
    }

    /** ipnstate.Status as JSON (BackendState, Self.TailscaleIPs, Self.ID, ...). */
    fun status(context: Context): JSONObject =
        JSONObject(call(ensureStarted(context), "GET", "status", null))

    /** Listener for tunnel up/down ([TailnetManager] switches the PBX route on it). */
    @Volatile var onVpnChanged: ((Boolean) -> Unit)? = null

    /**
     * Streams backend state changes (ipn.State ints) and login URLs until stopped.
     * Callbacks come on a Go thread.
     */
    fun watch(context: Context, onState: (Int) -> Unit, onLoginUrl: (String) -> Unit): libtailscale.NotificationManager =
        ensureStarted(context).watchNotifications(NOTIFY_INITIAL_STATE or NOTIFY_NO_NETMAP) { bytes ->
            val n = JSONObject(bytes.decodeToString())
            if (n.has("State")) onState(n.optInt("State"))
            n.optString("BrowseToURL").takeIf { it.isNotEmpty() }?.let(onLoginUrl)
        }

    /** Starts a browser login; the URL arrives through [watch]. */
    fun startInteractiveLogin(context: Context, hostname: String) {
        val a = ensureStarted(context)
        val prefs = JSONObject()
            .put("WantRunning", true)
            .put("CorpDNS", false)
            .put("RouteAll", false)
            .put("Hostname", hostname)
        call(a, "POST", "start", JSONObject().put("UpdatePrefs", prefs).toString())
        call(a, "POST", "login-interactive", null)
        connect(context)
    }

    internal fun onVpnActive(active: Boolean) {
        val changed = vpnActive != active
        vpnActive = active
        Log.i(TAG, "VPN active=$active")
        if (changed) onVpnChanged?.invoke(active)
    }

    internal fun onRevoked() {
        revoked = true
        onVpnActive(false)
    }

    private fun call(a: libtailscale.Application, method: String, endpoint: String, body: String?): String {
        val stream = body?.let { ByteStream(it.toByteArray()) }
        val resp = a.callLocalAPI(TIMEOUT_MS.toLong(), method, "/localapi/v0/$endpoint", stream)
        val text = resp.bodyBytes()?.decodeToString() ?: ""
        if (resp.statusCode() >= 400) {
            throw IllegalStateException("LocalAPI $method $endpoint -> ${resp.statusCode()}: $text")
        }
        return text
    }

    /** libtailscale.InputStream over a byte array: one chunk, then null (EOF). */
    private class ByteStream(private var data: ByteArray?) : libtailscale.InputStream {
        override fun read(): ByteArray? = data.also { data = null }
        override fun close() {
            data = null
        }
    }
}
