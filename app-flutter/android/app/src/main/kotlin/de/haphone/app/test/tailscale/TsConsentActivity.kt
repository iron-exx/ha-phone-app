package de.haphone.app.test.tailscale

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

/** Invisible host for the one-time system VPN consent dialog. */
class TsConsentActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        val intent = VpnService.prepare(this)
        if (intent == null) {
            TailnetManager.onConsentResult(this, true)
            finish()
        } else {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST) TailnetManager.onConsentResult(this, resultCode == RESULT_OK)
        finish()
    }

    private companion object {
        const val REQUEST = 7301
    }
}
