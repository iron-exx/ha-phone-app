package de.haphone.app.test.sip

/** Real implementor: PjsuaEndpointHolder. D-09/RESEARCH.md Pattern 3. */
interface IpChangeNotifier {
    fun handleIpChange()
}

/**
 * Pure decision logic invoked by the real ConnectivityManager.NetworkCallback
 * wired in HAPhoneTestApplication.onCreate() -- kept separate from that
 * platform class so this seam is unit-testable on the JVM (D-09).
 */
class NetworkChangeHandler(private val notifier: IpChangeNotifier) {
    /** Called from NetworkCallback.onAvailable() -- only once the new
     * network has a usable IP, never on old-interface teardown. */
    fun onNetworkAvailable() {
        notifier.handleIpChange()
    }
}
