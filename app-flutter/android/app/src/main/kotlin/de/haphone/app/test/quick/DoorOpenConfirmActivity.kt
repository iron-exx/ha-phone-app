package de.haphone.app.test.quick

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.widget.Toast
import de.haphone.app.test.HAPhoneTestApplication
import de.haphone.app.test.ring.DoorOpenClient
import de.haphone.app.test.ring.DoorOpenOutcome
import kotlin.concurrent.thread

/**
 * "Tür öffnen" from the quick settings tile or the app shortcut: always asks first
 * (a tap in the pocket must never open the door), then calls the PBX webhook like the
 * ringing screen's slider.
 */
class DoorOpenConfirmActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as HAPhoneTestApplication
        val doors = app.doorCodes.openRemoteNumbers()
        if (doors.isEmpty()) {
            Toast.makeText(this, "Keine Tür, die sich ohne Anruf öffnen lässt", Toast.LENGTH_LONG).show()
            finish()
            return
        }
        val builder = AlertDialog.Builder(this)
            .setTitle("Tür öffnen?")
            .setNegativeButton("Abbrechen") { _, _ -> finish() }
            .setOnCancelListener { finish() }
        if (doors.size == 1) {
            builder.setMessage("Tür ${doors[0]} wird geöffnet.")
                .setPositiveButton("Öffnen") { _, _ -> open(app, doors[0]) }
        } else {
            builder.setItems(doors.map { "Tür $it" }.toTypedArray()) { _, i -> open(app, doors[i]) }
        }
        builder.show()
    }

    private fun open(app: HAPhoneTestApplication, door: String) {
        val auth = app.getDeviceAuth()
        thread(name = "door-open") {
            val outcome = DoorOpenClient.open(
                auth["apiHost"].orEmpty(), auth["deviceId"].orEmpty(), auth["deviceToken"].orEmpty(), door,
            )
            runOnUiThread {
                val text = if (outcome == DoorOpenOutcome.OPENED) "Tür $door geöffnet" else outcome.message ?: "Fehler"
                Toast.makeText(app, text, Toast.LENGTH_LONG).show()
                finish()
            }
        }
    }
}
