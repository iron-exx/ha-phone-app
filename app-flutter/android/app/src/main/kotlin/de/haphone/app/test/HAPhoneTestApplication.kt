package de.haphone.app.test

import android.app.Application
import android.net.ConnectivityManager
import androidx.core.telecom.CallsManager
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

    /** The Telecom calls, each tied to its SIP call (replaces the single currentCallControlScope). Main thread. */
    val telecom = TelecomCalls()

    /** Ringing -> answered/declined/gone: ringtone, ringing screen, answer guard, ring timeout. */
    val incoming by lazy { IncomingCallFlow(this) }

    val callHistory by lazy { de.haphone.app.test.calls.CallHistoryStore(this) }
    val doorCodes by lazy { de.haphone.app.test.calls.DoorCodes(this) }
    val doorActions by lazy { de.haphone.app.test.calls.DoorActionClient(this) }

    /** Directory + favourites for the Android Auto screens (pushed from Dart). */
    val carDirectory by lazy { de.haphone.app.test.car.CarDirectoryStore(this) }

    /**
     * Starts an outgoing call, from Dart or from the Android Auto screens. Main thread.
     * False when two calls are already up. The first call is reported to Telecom first
     * (Report-First); the SIP INVITE only fires once Telecom has registered it.
     */
    fun placeCall(number: String): Boolean {
        val secondCall = currentCall != null
        if (!calls.beginOutgoing(number)) return false
        if (secondCall) {
            // Consultation call inside the running Telecom call: no new Telecom call.
            try {
                calls.bindOutgoing(sipCallController.makeCall(number))
            } catch (e: Exception) {
                android.util.Log.e("HAPhoneTestApplication", "second makeCall failed", e)
                calls.failOutgoing()
                CallEventBus.emitCallState(number, "outgoing", "lineEnded", e.message)
            }
            return true
        }
        val name = carDirectory.load().nameFor(number).ifBlank { number }
        callRegistration.reportOutgoingCall(
            number = number,
            displayName = name,
            onFailed = { e ->
                // Telecom refused, or the call was hung up before Telecom registered it.
                android.util.Log.w("HAPhoneTestApplication", "outgoing call not started: ${e.message}")
                if (calls.failOutgoing()) {
                    CallEventBus.emitCallState(number, "outgoing", "disconnected", e.message)
                    endTelecomSession(android.telecom.DisconnectCause.ERROR)
                }
            },
        ) { token ->
            // Runs later inside a coroutine, outside any caller's try/catch -- an uncaught PJSIP error here kills the process.
            try {
                val sipCallId = sipCallController.makeCall(number)
                calls.bindOutgoing(sipCallId)
                telecom.bindSipCall(token, sipCallId)
                SipService.setInCall(true)
            } catch (e: Exception) {
                android.util.Log.e("HAPhoneTestApplication", "makeCall failed", e)
                calls.failOutgoing()
                CallEventBus.emitCallState(number, "outgoing", "disconnected", e.message)
                endTelecomSession(android.telecom.DisconnectCause.ERROR)
            }
        }
        return true
    }

    private var answeredLocallyAt = 0L

    /** Our ringing screen answered; see [onAnsweredRemotely]. Main thread. */
    fun markAnsweredLocally() {
        answeredLocallyAt = android.os.SystemClock.elapsedRealtime()
    }

    /**
     * Telecom asked to answer (Android Auto, Bluetooth headset, watch), not our ringing
     * screen: close that screen and its notification and move the Flutter UI to the call.
     */
    fun onAnsweredRemotely() {
        incoming.stopAlerting()
        if (android.os.SystemClock.elapsedRealtime() - answeredLocallyAt < LOCAL_ANSWER_WINDOW_MS) {
            android.util.Log.i("HAPhoneTestApplication", "answer came from our ringing screen, no remote hand-off")
            return
        }
        android.util.Log.i("HAPhoneTestApplication", "answered remotely (car/headset), moving UI to the call")
        IncomingCallActivity.finishIfShowing()
        CallNotificationBuilder.cancel(this)
        sipMethodChannel?.invokeMethod("navigateTo", "active_call")
    }

    /** Telecom's onAnswer (car, Bluetooth headset, watch) for the call behind [token]. Main thread. */
    fun onTelecomAnswer(token: Int) {
        if (!telecom.isLive(token)) return
        val result = incoming.answer(telecom.sipCallIdFor(token), fromTelecom = true)
        if (result == IncomingCallFlow.AnswerResult.ANSWERED) onAnsweredRemotely()
    }

    /**
     * Telecom ended the call behind [token] (car/headset hang-up, Telecom teardown). Hangs up
     * exactly the SIP call it stands for -- not whatever happens to be on screen. A token we
     * released ourselves is no longer live and is ignored. Main thread.
     */
    fun onTelecomDisconnect(token: Int) {
        if (!telecom.isLive(token)) return
        val sipCallId = telecom.sipCallIdFor(token)
        telecom.onFailed(token)
        incoming.stopAlerting()
        if (sipCallId != null) {
            runCatching { sipCallController.hangup(sipCallId) }
                .onFailure { android.util.Log.w("HAPhoneTestApplication", "hangup of $sipCallId after Telecom disconnect failed", it) }
        } else if (calls.session.isEmpty) {
            // Push-announced call that never got its INVITE.
            endTelecomSession(android.telecom.DisconnectCause.LOCAL)
        }
    }

    /**
     * Telecom asked to hold/resume (Android Auto's in-call view). Only with a single call:
     * with two lines hold means swapping, which the phone UI handles. Main thread.
     */
    fun onTelecomHoldRequest(onHold: Boolean) {
        if (calls.session.other != null || currentCall?.onHold == onHold) return
        runCatching { sipCallController.hold(onHold) }
            .onFailure { android.util.Log.w("HAPhoneTestApplication", "Telecom hold request failed", it) }
        calls.setHold(onHold)
        currentCall?.let { CallEventBus.emitCallState(it.number, it.direction, if (onHold) "held" else "resumed") }
    }

    /** Telecom's mute state changed (car/headset mute button mutes the mic system-wide). */
    fun onTelecomMuteChanged(muted: Boolean) {
        val call = currentCall ?: return
        if (call.muted == muted) return
        calls.setMuted(muted)
        CallEventBus.emitCallState(call.number, call.direction, if (muted) "muted" else "unmuted")
    }

    /** In-app mute. Unmuting also lifts a system-wide mic mute a car/headset may have set via Telecom. */
    fun setMuted(muted: Boolean) {
        sipCallController.mute(muted)
        calls.setMuted(muted)
        if (!muted) {
            runCatching { getSystemService(android.media.AudioManager::class.java)?.isMicrophoneMute = false }
        }
    }

    /** In-app hold changed: mirror it to Telecom so the car/Bluetooth show the right state. */
    fun syncTelecomHold(onHold: Boolean) {
        if (calls.session.other != null) return
        val scope = telecom.current ?: return
        scope.launch {
            runCatching { if (onHold) scope.setInactive() else scope.setActive() }
                .onFailure { android.util.Log.w("HAPhoneTestApplication", "Telecom hold sync failed", it) }
        }
    }

    /** SIP call answered: an outgoing Telecom call must go from "dialling" to active (car shows it). */
    private fun markTelecomActive() {
        val scope = telecom.current ?: return
        scope.launch {
            runCatching { scope.setActive() }
                .onFailure { android.util.Log.w("HAPhoneTestApplication", "Telecom setActive failed", it) }
        }
    }

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

    /** Telecom reporting; independent of the SIP credentials (CallRegistration never touches PJSIP). */
    val callRegistration by lazy { CallRegistration(this) }

    /** Keeps the process (and so the SIP registration) alive in the background. */
    fun startSipService() {
        if (!hasValidCredentials()) return
        // From the background (watchdog, alarm) Android 12+ may refuse; the alarm and an
        // exempted battery optimisation normally allow it, the watchdog retries otherwise.
        runCatching {
            androidx.core.content.ContextCompat.startForegroundService(
                this, android.content.Intent(this, SipService::class.java),
            )
        }.onFailure { android.util.Log.w(de.haphone.app.test.reach.ReachabilityMonitor.TAG, "could not start service", it) }
        de.haphone.app.test.reach.WatchdogWorker.ensureScheduled(this)
    }

    /** Last call gone: release Telecom, ringing UI, ringtone, notifications and the video window. */
    fun endTelecomSession(cause: Int) {
        incoming.stopAlerting()
        de.haphone.app.test.calls.AudioRouting.detach()
        releaseTelecomCall(cause)
        CallNotificationBuilder.cancel(this)
        de.haphone.app.test.sip.VideoSurfaceBinder.reset()
        IncomingCallActivity.finishIfShowing()
        SipService.setInCall(false)
    }

    /** Releases every Telecom call; one not registered yet is disconnected as soon as it is. */
    fun releaseTelecomCall(cause: Int) {
        telecom.releaseAll(cause)
    }

    /** Called by SipChannelHandler after saveCredentials so a credential
     * change takes effect on the next call/register, not only after a
     * process restart. */
    fun refreshSipCredentials() {
        runCatching { _sipCallController?.unregister() }
        _sipCallController = buildSipCallController()
    }

    private fun buildSipCallController(): SipCallController {
        pjsuaEndpointHolder.start()
        val (host, port, username, password) = getSipCredentialsForRegistration()
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
        ShortWakeLock.attach(this)
        de.haphone.app.test.reach.ReachabilityMonitor.attach(this)
        de.haphone.app.test.ring.RingPolicyStore.attach(this) { number ->
            doorCodes.forNumber(number).isNotBlank() || doorCodes.hasOpenRemote(number) ||
                doorActions.labelsFor(number).isNotEmpty()
        }
        CallNotificationBuilder.ensureChannel(this)

        // Fix: CallRegistration.registerApp() previously had zero call
        // sites anywhere in the app, so this process was never actually
        // declared a Telecom self-managed calling app -- called directly
        // here (not via `callRegistration.registerApp()`) so this cheap,
        // SIP-independent registration doesn't force PjsuaEndpointHolder.start()
        // eagerly at process start, which would undo the lazy-init intent.
        CallsManager(this).registerAppWithTelecom(CallsManager.CAPABILITY_BASELINE)

        de.haphone.app.test.sip.SipCallEvents.onCallDisconnected = { callId, reason ->
            incoming.onCallEnded(callId)
            val nothingLeft = calls.ended(callId)
            de.haphone.app.test.car.CarScreens.refreshAll() // Verlauf in Android Auto
            CallNotificationBuilder.cancelWaiting(this)
            if (nothingLeft) {
                CallEventBus.emitCallState("", "", "disconnected", reason)
                endTelecomSession(android.telecom.DisconnectCause.REMOTE)
            } else {
                // One of two calls ended: the other stays (on hold) on the call screen, and the
                // Telecom call now stands for it.
                calls.session.focused?.let { telecom.moveSipCall(callId, it.callId) }
                CallEventBus.emitCallState(currentCall?.number.orEmpty(), currentCall?.direction.orEmpty(), "lineEnded", reason)
            }
        }
        de.haphone.app.test.sip.SipCallEvents.onIncomingCall = { call -> incoming.onIncoming(call) }
        de.haphone.app.test.sip.SipCallEvents.onCallConfirmed = { callId ->
            incoming.onConfirmed(callId)
            calls.confirmed(callId)
            SipService.setInCall(true)
            if (calls.session.other == null) markTelecomActive()
        }

        // D-09: mid-call network-switch resilience (RESEARCH.md Pattern 3) --
        // observe platform network changes for the app process lifetime and
        // route them through the testable NetworkChangeHandler seam.
        val connectivityManager = getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            // Delivered on a ConnectivityManager binder thread; PJSIP may only be driven
            // from the thread it was started on (main), so hop there first.
            override fun onAvailable(network: android.net.Network) {
                // Doze: keep the CPU up until PJSIP has restarted its transport (auto-released).
                ShortWakeLock.acquire(ShortWakeLock.NETWORK_CHANGE)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    de.haphone.app.test.reach.ReachabilityMonitor.onIpChange()
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
        // Tailscale tunnel back up after a restart (only if paired with it and consent holds).
        de.haphone.app.test.tailscale.TailnetManager.resume(this)
    }

    /** Raw stored values only -- what the Settings screen should display. */
    fun getStoredCredentials(): Map<String, String> = SecurePrefs.read(this) { prefs ->
        mapOf(
            "host" to prefs.getString("sip_host", "").orEmpty(),
            "port" to prefs.getString("sip_port", "").orEmpty(),
            "username" to prefs.getString("sip_username", "").orEmpty(),
            "password" to prefs.getString("sip_password", "").orEmpty(),
        )
    }

    /** Never throws: called from boot/alarm/watchdog paths where a crash would stop reachability. */
    fun hasValidCredentials(): Boolean = runCatching {
        getStoredCredentials().values.all { it.isNotBlank() }
    }.onFailure { android.util.Log.e("HAPhoneTestApplication", "credentials unreadable", it) }
        .getOrDefault(false)

    fun saveCredentials(host: String, port: String, username: String, password: String) {
        SecurePrefs.get(this).edit().apply {
            putString("sip_host", host)
            putString("sip_port", port)
            putString("sip_username", username)
            putString("sip_password", password)
            apply()
        }
    }

    /** Device secret from QR pairing, needed for the phone-facing /api/mobile endpoints. */
    fun saveDeviceAuth(apiHost: String, deviceId: String, deviceToken: String) {
        SecurePrefs.get(this).edit().apply {
            putString("api_host", apiHost)
            putString("device_id", deviceId)
            putString("device_token", deviceToken)
            apply()
        }
    }

    fun getDeviceAuth(): Map<String, String> = SecurePrefs.read(this) { prefs ->
        mapOf(
            "apiHost" to de.haphone.app.test.tailscale.TailnetRoute.apiHost(
                prefs.getString("api_host", "").orEmpty(),
                prefs.getString("ts_pbx_ip", null),
                de.haphone.app.test.tailscale.TailnetManager.running,
            ),
            "deviceId" to prefs.getString("device_id", "").orEmpty(),
            "deviceToken" to prefs.getString("device_token", "").orEmpty(),
        )
    }

    fun clearCredentials() {
        SecurePrefs.get(this).edit().clear().apply()
        de.haphone.app.test.reach.ReachabilityMonitor.stop(this)
    }

    /** Credentials come only from provisioning (QR pairing / Settings); empty until then. */
    private fun getSipCredentialsForRegistration(): List<String> {
        val c = getStoredCredentials()
        // Over the tailnet while our Tailscale tunnel runs, else the LAN address from pairing.
        val host = de.haphone.app.test.tailscale.TailnetRoute.sipHost(
            c["host"].orEmpty(),
            de.haphone.app.test.tailscale.TailnetManager.pbxTailnetIp(this),
            de.haphone.app.test.tailscale.TailnetManager.running,
        )
        val port = de.haphone.app.test.tailscale.TailnetRoute.sipPort(
            c["port"].orEmpty(),
            de.haphone.app.test.tailscale.TailnetManager.tailnetSipPort(this),
            de.haphone.app.test.tailscale.TailnetManager.pbxTailnetIp(this),
            de.haphone.app.test.tailscale.TailnetManager.running,
        )
        return listOf(host, port, c["username"].orEmpty(), c["password"].orEmpty())
    }

    companion object {
        /** Telecom echoes our own answer within a few seconds at most. */
        private const val LOCAL_ANSWER_WINDOW_MS = 5_000L
        const val FLUTTER_ENGINE_ID = "de.haphone.app.test.main_engine"
    }
}
