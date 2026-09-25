package de.haphone.app.test.tailscale

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import de.haphone.app.test.BuildConfig
import kotlin.concurrent.thread

/**
 * adb hook for the Tailscale spike, debug builds only:
 *
 *   adb shell am broadcast -n de.haphone.app.test/.tailscale.TsDebugReceiver \
 *       -a join --es key tskey-auth-... --es host haphone-emu
 *   ... -a login --es host haphone-emu   (browser login, URL in logcat)
 *   ... -a status | -a connect | -a disconnect | -a logout
 *
 * VPN consent in the emulator without UI: adb shell appops set de.haphone.app.test ACTIVATE_VPN allow
 * Results go to logcat, tag "TsDebug".
 */
class TsDebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return
        val app = context.applicationContext
        val pending = goAsync()
        thread(name = "ts-debug") {
            try {
                when (intent.action) {
                    "join" -> {
                        if (Tailscale.consentIntent(app) != null) {
                            Log.w(TAG, "no VPN consent yet (appops ACTIVATE_VPN allow)")
                            return@thread
                        }
                        val key = intent.getStringExtra("key").orEmpty()
                        val host = intent.getStringExtra("host") ?: "haphone-debug"
                        Tailscale.loginWithAuthKey(app, key, host, intent.getStringExtra("control"))
                        Log.i(TAG, "join sent for $host")
                    }
                    "login" -> {
                        if (Tailscale.consentIntent(app) != null) {
                            Log.w(TAG, "no VPN consent yet (appops ACTIVATE_VPN allow)")
                            return@thread
                        }
                        val host = intent.getStringExtra("host") ?: "haphone-debug"
                        Tailscale.loginInteractive(
                            app,
                            host,
                            onUrl = { Log.i(TAG, "LOGIN URL: $it") },
                            onRunning = { Log.i(TAG, "tailnet running") },
                        )
                    }
                    "connect" -> Tailscale.connect(app)
                    "disconnect" -> Tailscale.disconnect(app)
                    "logout" -> Tailscale.logout(app)
                    "status" -> {
                        val st = Tailscale.status(app)
                        val self = st.optJSONObject("Self")
                        Log.i(
                            TAG,
                            "state=${st.optString("BackendState")} vpn=${Tailscale.vpnActive} " +
                                "revoked=${Tailscale.revoked} ips=${self?.optJSONArray("TailscaleIPs")} " +
                                "id=${self?.optString("ID")} dns=${self?.optString("DNSName")} " +
                                "tailnet=${st.optJSONObject("CurrentTailnet")?.optString("Name")}",
                        )
                        st.optJSONObject("Peer")?.let { peers ->
                            for (k in peers.keys()) {
                                val p = peers.getJSONObject(k)
                                Log.i(
                                    TAG,
                                    "peer ${p.optString("HostName")} ${p.optJSONArray("TailscaleIPs")} " +
                                        "online=${p.optBoolean("Online")} relay=${p.optString("Relay")} " +
                                        "cur=${p.optString("CurAddr")}",
                                )
                            }
                        }
                    }
                    else -> Log.w(TAG, "unknown action ${intent.action}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "${intent.action} failed", e)
            } finally {
                pending.finish()
            }
        }
    }

    private companion object {
        const val TAG = "TsDebug"
    }
}
