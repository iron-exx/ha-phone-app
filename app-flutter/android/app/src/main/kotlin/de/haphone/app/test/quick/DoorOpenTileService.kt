package de.haphone.app.test.quick

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import de.haphone.app.test.HAPhoneTestApplication

/** Quick settings tile "Tür öffnen" (with confirmation, see [DoorOpenConfirmActivity]). */
class DoorOpenTileService : TileService() {
    override fun onStartListening() {
        val available = (application as HAPhoneTestApplication).doorCodes.openRemoteNumbers().isNotEmpty()
        qsTile?.apply {
            state = if (available) Tile.STATE_INACTIVE else Tile.STATE_UNAVAILABLE
            label = "Tür öffnen"
            updateTile()
        }
    }

    override fun onClick() {
        val intent = Intent(this, DoorOpenConfirmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val launch = {
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
                )
            } else {
                @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
                startActivityAndCollapse(intent)
            }
        }
        // Opening the door needs an unlocked phone.
        if (isLocked) unlockAndRun { launch() } else launch()
    }
}
