package de.haphone.app.test

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import androidx.core.app.NotificationManagerCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import de.haphone.app.test.sip.NetworkChangeHandler
import de.haphone.app.test.sip.PjsuaEndpointHolder
import de.haphone.app.test.sip.SipCallController
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.launch

/**
 * Ensures the incoming-call notification channel exists before any FCM
 * message can arrive -- registering it lazily inside CallNotificationBuilder
 * would race the very first push. Also owns the process-lifetime PJSUA2
 * Endpoint (PjsuaEndpointHolder) and the platform network-change observer
 * that drives its D-09 mid-call network-switch recovery path.
 *
 * Flutter migration: also registers the app with Telecom eagerly (moved
 * out of the never-called CallRegistration.registerApp() -- see below) and
 * pre-warms a cached FlutterEngine (executeDartEntrypoint here, not left
 * to FlutterActivity's own attach) so IncomingCallActivity's post-answer
 * hand-off to the Dart UI doesn't pay full engine-creation cost on an
 * already time-critical path.
 *
 * KNOWN ISSUE (live-device confirmed, 2026-09-22, on a OnePlus 3 / Android
 * 9): this pre-warming makes Dart's main()/runApp() run immediately, here,
 * before MainActivity exists to attach and register the sip_calls/
 * call_events channel handlers in configureFlutterEngine() -- so
 * HomeScreen.initState()'s first platform-channel call
 * (hasValidCredentials) can race ahead of that registration and the
 * resulting Future can sit unresolved for a while (observed: stuck on the
 * loading spinner until navigating to Settings and back, which triggers a
 * second, by-then-working call). Tried removing executeDartEntrypoint()
 * here entirely (leaving Dart to start only once FlutterActivity attaches)
 * -- that was WORSE: no UI ever rendered at all, blank screen indefinitely
 * (reverted). Real fix belongs on the Dart side (retry hasValidCredentials
 * with a short backoff instead of a single await) -- not yet done; this
 * comment exists so the next person doesn't reintroduce the same "just
 * remove the pre-warm" attempt without knowing it was already tried and
 * made things worse.
 */
class HAPhoneTestApplication : Application() {
    val pjsuaEndpointHolder = PjsuaEndpointHolder()
    private val networkChangeHandler = NetworkChangeHandler(pjsuaEndpointHolder)
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Blocker fix: the only source ActiveCallActivity (Plan 06) reads for
    // CallControlScope.availableEndpoints/requestEndpointChange (Audio
    // Routing, CALL-01). Stashed by CallRegistration.reportIncomingCall AND
    // reportOutgoingCall's trailing lambda (both directions), overwritten
    // each time a new call is reported so it always reflects the current call.
    var currentCallControlScope: CallControlScope? = null

    val callHistory by lazy { de.haphone.app.test.calls.CallHistoryStore(this) }
    val doorCodes by lazy { de.haphone.app.test.calls.DoorCodes(this) }
    val doorActions by lazy { de.haphone.app.test.calls.DoorActionClient(this) }

    /** Runs a door station's HA action off the main thread; [onDone] gets null or an error, on main. */
    fun runDoorAction(number: String, index: Int, onDone: (String?) -> Unit) {
        val auth = getDeviceAuth()
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        Thread {
            val error = doorActions.run(auth["apiHost"].orEmpty(), auth["deviceId"].orEmpty(), auth["deviceToken"].orEmpty(), number, index)
            main.post { onDone(error) }
        }.start()
    }

    /** Up to two calls (on screen + held/waiting), history and UI events. Main thread only. */
    /** Native -> Dart calls (navigateTo); set up with the engine in onCreate. */
    var sipMethodChannel: io.flutter.plugin.common.MethodChannel? = null
        private set

    val calls by lazy { de.haphone.app.test.calls.CallCoordinator(callHistory, doorCodes, doorActions::labelsFor) }

    /** The call on screen, null when idle. */
    val currentCall: de.haphone.app.test.calls.CurrentCall? get() = calls.currentCall

    // Rebuildable, unlike a bare `by lazy {}`: credentials can now change at
    // runtime via the Flutter Settings screen (SipChannelHandler.saveCredentials),
    // and a bare `by lazy` would cache the first-read credentials for the
    // process lifetime, silently ignoring a later save until restart.
    // pjsuaEndpointHolder.start() is idempotent (no-ops if already started),
    // so calling it here is what actually performs this app's "lazy PJSIP
    // init" -- the endpoint is created on first real use, not at process
    // start, but IS guaranteed to exist before any SipCallController method
    // runs (a prior regression removed the call site entirely; this is that
    // fix, now centralized in one place instead of scattered per-Activity).
    private var _sipCallController: SipCallController? = null
    val sipCallController: SipCallController
        get() = _sipCallController ?: buildSipCallController().also { _sipCallController = it }

    private var _callRegistration: CallRegistration? = null
    val callRegistration: CallRegistration
        get() = _callRegistration ?: CallRegistration(this, sipCallController).also { _callRegistration = it }

    /** Called by SipChannelHandler after saveCredentials so a credential
     * change takes effect on the next call/register, not only after a
     * process restart. */
    /**
     * A SIP INVITE arrived while registered: hand it to Telecom (so it behaves like a
     * normal call: audio focus, Bluetooth, car) and show the ringing UI.
     */
    private fun showIncomingSipCall(call: de.haphone.app.test.sip.IncomingSipCall) {
        val callId = call.number.ifBlank { "unknown" }
        val callType = if (call.hasVideo) "video" else "audio"
        val role = calls.beginIncoming(call.callId, call.number, call.displayName, call.hasVideo)
        if (role != de.haphone.app.test.calls.CallSession.IncomingRole.FOCUSED) {
            // Call waiting: the Telecom call and the call screen stay; Dart shows the waiting banner.
            CallNotificationBuilder.showWaiting(this, callId, call.displayName)
            return
        }
        callRegistration.reportIncomingCall(callId, displayName = call.displayName) {}
        CallNotificationBuilder.show(
            this, callId, callType, isValid = true, isExpired = false, callerName = call.displayName,
        )
        // The full-screen intent only fires on a locked/off screen; with the phone in
        // use it would just be a heads-up, so open the ringing screen directly.
        runCatching {
            startActivity(
                IncomingCallActivity.intent(this, callId, callType, call.displayName)
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }.onFailure { android.util.Log.w("HAPhoneTestApplication", "could not open ringing screen", it) }
    }

    /** Keeps the process (and so the SIP registration) alive in the background. */
    fun startSipService() {
        if (!hasValidCredentials()) return
        androidx.core.content.ContextCompat.startForegroundService(
            this, android.content.Intent(this, SipService::class.java),
        )
    }

    /** Last call gone: release Telecom, ringing UI, notifications and the video window. */
    fun endTelecomSession(cause: Int) {
        de.haphone.app.test.calls.AudioRouting.detach()
        releaseTelecomCall(cause)
        CallNotificationBuilder.cancel(this)
        de.haphone.app.test.sip.VideoSurfaceBinder.reset()
        IncomingCallActivity.finishIfShowing()
    }

    fun releaseTelecomCall(cause: Int) {
        val scope = currentCallControlScope ?: return
        currentCallControlScope = null
        scope.launch {
            runCatching { scope.disconnect(android.telecom.DisconnectCause(cause)) }
                .onFailure { android.util.Log.w("HAPhoneTestApplication", "Telecom disconnect failed", it) }
        }
    }

    fun refreshSipCredentials() {
        runCatching { _sipCallController?.unregister() }
        _sipCallController = buildSipCallController()
        _callRegistration = CallRegistration(this, requireNotNull(_sipCallController))
    }

    private fun buildSipCallController(): SipCallController {
        pjsuaEndpointHolder.start()
        val (host, port, username, password) = getSipCredentialsForRegistration(this)
        val sipDomain = "$host:$port"
        return SipCallController(
            sipOps = pjsuaEndpointHolder.asSipCallOperations(
                username = username,
                password = password,
                domain = sipDomain,
            ),
            sipDomain = sipDomain,
        )
    }

    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(
            CallNotificationBuilder.CHANNEL_ID,
            "HA-Phone Test Calls",
            NotificationManager.IMPORTANCE_HIGH,
        )
        NotificationManagerCompat.from(this).createNotificationChannel(channel)

        // Fix: CallRegistration.registerApp() previously had zero call
        // sites anywhere in the app, so this process was never actually
        // declared a Telecom self-managed calling app -- called directly
        // here (not via `callRegistration.registerApp()`) so this cheap,
        // SIP-independent registration doesn't force PjsuaEndpointHolder.start()
        // eagerly at process start, which would undo the lazy-init intent.
        CallsManager(this).registerAppWithTelecom(CallsManager.CAPABILITY_BASELINE)

        de.haphone.app.test.sip.SipCallEvents.onCallDisconnected = { callId, reason ->
            val nothingLeft = calls.ended(callId)
            CallNotificationBuilder.cancelWaiting(this)
            if (nothingLeft) {
                CallEventBus.emitCallState("", "", "disconnected", reason)
                endTelecomSession(android.telecom.DisconnectCause.REMOTE)
            } else {
                // One of two calls ended: the other stays (on hold) on the call screen.
                CallEventBus.emitCallState(currentCall?.number.orEmpty(), currentCall?.direction.orEmpty(), "lineEnded", reason)
            }
        }
        de.haphone.app.test.sip.SipCallEvents.onIncomingCall = { call -> showIncomingSipCall(call) }
        de.haphone.app.test.sip.SipCallEvents.onCallConfirmed = { callId -> calls.confirmed(callId) }

        // D-09: mid-call network-switch resilience (RESEARCH.md Pattern 3) --
        // observe platform network changes for the app process lifetime and
        // route them through the testable NetworkChangeHandler seam.
        val connectivityManager = getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            // Delivered on a ConnectivityManager binder thread; PJSIP may only be driven
            // from the thread it was started on (main), so hop there first.
            override fun onAvailable(network: android.net.Network) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    networkChangeHandler.onNetworkAvailable()
                }
            }
        }
        connectivityManager?.registerDefaultNetworkCallback(callback)
        networkCallback = callback

        val flutterEngine = FlutterEngine(this)
        // Channels are registered HERE, before Dart starts: registering them only in
        // MainActivity.configureFlutterEngine raced Dart's first calls on a cold start,
        // and a lost EventChannel listen meant the call screen never got a single event.
        val handler = SipChannelHandler(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        sipMethodChannel = io.flutter.plugin.common.MethodChannel(messenger, MainActivity.SIP_METHOD_CHANNEL)
            .also { it.setMethodCallHandler(handler) }
        io.flutter.plugin.common.EventChannel(messenger, MainActivity.SIP_EVENT_CHANNEL).setStreamHandler(handler)
        flutterEngine.platformViewsController.registry
            .registerViewFactory(RemoteVideoViewFactory.VIEW_TYPE, RemoteVideoViewFactory())
        flutterEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(FLUTTER_ENGINE_ID, flutterEngine)
    }

    /** Raw stored values only (no BuildConfig fallback) -- what the
     * Settings screen should display, matching the old SettingsActivity's
     * behavior of showing exactly what's saved, never a hidden dev default. */
    fun getStoredCredentials(): Map<String, String> {
        val prefs = getEncryptedPrefs(this)
        return mapOf(
            "host" to (prefs.getString("sip_host", "") ?: ""),
            "port" to (prefs.getString("sip_port", "") ?: ""),
            "username" to (prefs.getString("sip_username", "") ?: ""),
            "password" to (prefs.getString("sip_password", "") ?: ""),
        )
    }

    fun hasValidCredentials(): Boolean {
        val prefs = getEncryptedPrefs(this)
        return prefs.getString("sip_host", "")?.isNotBlank() == true &&
            prefs.getString("sip_port", "")?.isNotBlank() == true &&
            prefs.getString("sip_username", "")?.isNotBlank() == true &&
            prefs.getString("sip_password", "")?.isNotBlank() == true
    }

    fun saveCredentials(host: String, port: String, username: String, password: String) {
        getEncryptedPrefs(this).edit().apply {
            putString("sip_host", host)
            putString("sip_port", port)
            putString("sip_username", username)
            putString("sip_password", password)
            apply()
        }
    }

    /** Device secret from QR pairing, needed for the phone-facing /api/mobile endpoints. */
    fun saveDeviceAuth(apiHost: String, deviceId: String, deviceToken: String) {
        getEncryptedPrefs(this).edit().apply {
            putString("api_host", apiHost)
            putString("device_id", deviceId)
            putString("device_token", deviceToken)
            apply()
        }
    }

    fun getDeviceAuth(): Map<String, String> {
        val prefs = getEncryptedPrefs(this)
        return mapOf(
            "apiHost" to (prefs.getString("api_host", "") ?: ""),
            "deviceId" to (prefs.getString("device_id", "") ?: ""),
            "deviceToken" to (prefs.getString("device_token", "") ?: ""),
        )
    }

    fun clearCredentials() {
        getEncryptedPrefs(this).edit().clear().apply()
    }

    /** Used internally for actual SIP registration -- falls back to
     * BuildConfig (gitignored local.properties-sourced dev test extension)
     * when nothing is stored yet, so a fresh checkout still registers
     * against the dev test extension without requiring Settings entry. */
    private fun getSipCredentialsForRegistration(context: Context): List<String> {
        val prefs = getEncryptedPrefs(context)
        val host = prefs.getString("sip_host", "") ?: BuildConfig.SIP_TEST_HOST
        val port = prefs.getString("sip_port", "") ?: BuildConfig.SIP_TEST_PORT
        val username = prefs.getString("sip_username", "") ?: BuildConfig.SIP_TEST_USERNAME
        val password = prefs.getString("sip_password", "") ?: BuildConfig.SIP_TEST_PASSWORD
        return listOf(host, port, username, password)
    }

    private fun getEncryptedPrefs(context: Context): SharedPreferences {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        return EncryptedSharedPreferences.create(
            "haphone_prefs",
            masterKeyAlias,
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    companion object {
        const val FLUTTER_ENGINE_ID = "de.haphone.app.test.main_engine"
    }
}
