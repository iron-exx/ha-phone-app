package de.haphone.app.test.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import java.lang.ref.WeakReference

/**
 * Android Auto entry point (Car App Library, category CALLING). The templated screens
 * only list and dial; the in-call view itself comes from Android Auto, fed by our
 * Telecom (core-telecom CallsManager) integration in CallRegistration.
 */
class HaPhoneCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            // Debug builds: also the Desktop Head Unit and sideloaded hosts.
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: Intent): Screen = CarRootScreen(carContext)
    }
}

/** Open car screens, so a directory push from Dart or a finished call refreshes them. Main thread only. */
object CarScreens {
    private val screens = mutableListOf<WeakReference<Screen>>()

    fun register(screen: Screen) {
        screens.removeAll { it.get() == null }
        screens += WeakReference(screen)
    }

    fun refreshAll() {
        screens.removeAll { it.get() == null }
        screens.forEach { ref -> runCatching { ref.get()?.invalidate() } }
    }
}
