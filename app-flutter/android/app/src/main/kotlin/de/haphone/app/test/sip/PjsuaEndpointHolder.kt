package de.haphone.app.test.sip

import org.pjsip.pjsua2.Endpoint
import org.pjsip.pjsua2.EpConfig

/**
 * Owns a single PJSUA2 Endpoint for the app process lifetime (RESEARCH.md
 * "tied to app process lifetime"). Initialized once from
 * HAPhoneTestApplication.onCreate(); never re-created per-call. Applies
 * CodecPriorities (CALL-01/D-07) immediately after libStart().
 *
 * NOTE (RESEARCH.md Pitfall 1): PJSIP 2.17 changed `Call::acc` from
 * `Account&` to `Account*` -- any code ported from older PJSUA2 samples
 * using `.acc.` member access must use `->` instead.
 */
data class IncomingSipCall(
    val callId: Int,
    val number: String,
    val displayName: String,
    val hasVideo: Boolean,
    /** Arrived while another call is up (call waiting): ring in-call, do not take over. */
    val waiting: Boolean = false,
)

/** Main-thread notifications from the PJSIP layer. */
object SipCallEvents {
    /** A SIP call ended (remote hangup/cancel, failure, or local hangup). */
    var onCallDisconnected: ((callId: Int, reason: String) -> Unit)? = null
    /** A new SIP INVITE is ringing (already answered with 180, or 183 early media for video). */
    var onIncomingCall: ((IncomingSipCall) -> Unit)? = null
    /** A call was answered (SIP CONFIRMED). */
    var onCallConfirmed: ((callId: Int) -> Unit)? = null
}

/** Parses `"Name" <sip:16@host>` / `<sip:16@host>` / `sip:16@host` into (number, name). */
internal fun parseRemoteUri(remoteUri: String): Pair<String, String> {
    val number = Regex("sips?:([^@;>]+)").find(remoteUri)?.groupValues?.get(1).orEmpty()
    val name = Regex("^\\s*\"([^\"]*)\"").find(remoteUri)?.groupValues?.get(1)
        ?: remoteUri.substringBefore('<', "").trim()
    return number to name.ifBlank { number }
}

/**
 * Binds the incoming video window of the ringing/active call to whatever Surface
 * the UI currently shows. Main thread only. A window must be detached (null
 * surface) before its Surface is destroyed, or the renderer draws into a dead one.
 */
object VideoSurfaceBinder {
    private var windowId = -1
    private var surface: android.view.Surface? = null

    fun setWindowId(id: Int) {
        windowId = id
        apply()
    }

    fun setSurface(s: android.view.Surface?) {
        surface = s
        apply()
    }

    /** Detach only if [s] is still the bound surface: a closing screen must not unbind the next one's. */
    fun clearSurface(s: android.view.Surface) {
        if (surface === s) setSurface(null)
    }

    fun reset() {
        surface = null
        apply()
        windowId = -1
    }

    val hasVideo: Boolean get() = windowId >= 0

    private fun apply() {
        if (windowId < 0) return
        runCatching {
            val handle = org.pjsip.pjsua2.VideoWindowHandle()
            handle.handle.setWindow(surface)
            org.pjsip.pjsua2.VideoWindow(windowId).setWindow(handle)
        }.onFailure { android.util.Log.w("PJSIP", "binding video window $windowId failed", it) }
    }
}

private class LogcatWriter : org.pjsip.pjsua2.LogWriter() {
    override fun write(entry: org.pjsip.pjsua2.LogEntry) {
        android.util.Log.d("PJSIP", entry.msg.trimEnd())
    }
}

/**
 * Endpoint subclass only for [onTransportState]: a dead TLS connection means the PBX
 * can no longer reach us, so ReachabilityMonitor re-registers at once (with backoff).
 * Called on the PJSIP worker thread -> hop to main.
 */
private class HAPhoneEndpoint : Endpoint() {
    override fun onTransportState(prm: org.pjsip.pjsua2.OnTransportStateParam) {
        val type = runCatching { prm.type }.getOrDefault("?")
        val state = prm.state
        val lastError = prm.lastError
        if (state == org.pjsip.pjsua2.pjsip_transport_state.PJSIP_TP_STATE_CONNECTED) checkPin(prm, type)
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            de.haphone.app.test.reach.ReachabilityMonitor.onTransportState(type, state, lastError)
        }
    }

    /**
     * Cert pinning for SIP TLS (verifyServer stays off: the box's cert is self-signed and
     * reached by LAN and tailnet IP). This callback runs before PJSIP flushes the queued
     * REGISTER, so shutting the transport down here means nothing is sent to a wrong peer.
     * Must stay synchronous on the PJSIP thread for exactly that reason.
     */
    private fun checkPin(prm: org.pjsip.pjsua2.OnTransportStateParam, type: String) {
        val isTls = type.contains("TLS", ignoreCase = true)
        val pem = runCatching { prm.tlsInfo.takeUnless { it.isEmpty }?.remoteCertInfo?.raw }.getOrNull()
        if (de.haphone.app.test.net.PbxTls.acceptSipTls(de.haphone.app.test.net.PbxTls.current, isTls, pem)) return
        android.util.Log.e("PJSIP", "TLS: PBX certificate does not match the paired fingerprint, dropping connection")
        de.haphone.app.test.net.PbxTls.lastSipPinMismatchMs = System.currentTimeMillis()
        runCatching { transportShutdown(prm.hnd) }
    }
}

class PjsuaEndpointHolder : IpChangeNotifier {
    private val endpoint: Endpoint = HAPhoneEndpoint()
    private var started = false
    private var libInitialized = false
    // Must stay strongly referenced: PJSIP holds only a native pointer, a GC'd writer crashes on the next log line.
    private val logWriter = LogcatWriter()

    fun start() {
        if (started) return
        // libCreate/libInit must never run twice: a retry after a partial failure corrupts pjsua state (SIGSEGV in pjsua_handle_events).
        if (!libInitialized) {
            endpoint.libCreate()
            val epConfig = EpConfig()
            epConfig.logConfig.level = 4
            epConfig.logConfig.consoleLevel = 4
            epConfig.logConfig.writer = logWriter
            // A PBX without STUN must not block calls (see useStunServer).
            epConfig.uaConfig.stunIgnoreFailure = true
            endpoint.libInit(epConfig)
            endpoint.libStart()
            libInitialized = true
        }
        // Fix (confirmed via a live-device crash, 2026-09-22): Account.create()
        // -> pjsua_acc_add() hard-asserts a transport already exists
        // ("pjsua_var.tpdata[0].data.ptr != NULL"), aborting the whole
        // process (SIGABRT) the instant register()/makeCall() actually ran
        // for the first time. libCreate()/libInit()/libStart() alone never
        // create one -- this was a pre-existing gap in both platforms'
        // PJSIP bridge (iOS's PjsuaBridge.mm has the identical omission),
        // just never reached before now because nothing upstream of it
        // (PJSIP init, provisioning) worked yet either. Create the TLS
        // transport this app's accounts actually use (matches the
        // verifyServer=false / SRTP-mandatory config in
        // asSipCallOperations below) once, for the process lifetime.
        val transportConfig = org.pjsip.pjsua2.TransportConfig()
        transportConfig.port = 0L // client-only; let the OS pick a local port
        val tlsConfig = org.pjsip.pjsua2.TlsConfig()
        // DEV-ONLY, mirrors the account-level verifyServer=false below:
        // self-signed cert on the LAN-only test transport (D-05). Revisit
        // before a later production-transport phase.
        tlsConfig.verifyServer = false
        transportConfig.tlsConfig = tlsConfig
        endpoint.transportCreate(org.pjsip.pjsua2.pjsip_transport_type_e.PJSIP_TRANSPORT_TLS, transportConfig)
        applyCodecPriorities(object : CodecPriorityApplier {
            override fun setPriority(codecId: String, priority: Int) {
                endpoint.codecSetPriority(codecId, priority.toShort())
            }
        })
        // Door stations send H.264; decode via Android MediaCodec. Empty when PJSIP
        // was built without PJMEDIA_HAS_VIDEO, in which case calls stay audio-only.
        runCatching {
            for (codec in endpoint.videoCodecEnum2()) {
                val prio: Short = if (codec.codecId.startsWith("H264", ignoreCase = true)) 255 else 0
                endpoint.videoCodecSetPriority(codec.codecId, prio)
                android.util.Log.i("PJSIP", "video codec ${codec.codecId} priority=$prio")
                if (prio > 0) allowLargeDecodedFrames(codec.codecId)
            }
        }.onFailure { android.util.Log.w("PJSIP", "video codec setup failed", it) }
        started = true
    }

    /**
     * PJSIP sizes the decoded-picture buffer from the codec's default decFmt (352x288). Door
     * stations send 640x480 or 720p, which no longer fits: nearly every frame failed with
     * PJMEDIA_CODEC_EFRMTOOSHORT and the preview froze. Allow up to 1080p and advertise
     * level 3.1 so the door may send 720p.
     */
    private fun allowLargeDecodedFrames(codecId: String) {
        runCatching {
            val param = endpoint.getVideoCodecParam(codecId)
            param.decFmt.width = VideoDecodeLimits.MAX_WIDTH.toLong()
            param.decFmt.height = VideoDecodeLimits.MAX_HEIGHT.toLong()
            val fmtp = org.pjsip.pjsua2.CodecFmtpVector()
            VideoDecodeLimits.h264Fmtp.forEach { (name, value) ->
                fmtp.add(org.pjsip.pjsua2.CodecFmtp().also { it.name = name; it.`val` = value })
            }
            param.decFmtp = fmtp
            endpoint.setVideoCodecParam(codecId, param)
            android.util.Log.i("PJSIP", "video codec $codecId decode up to ${VideoDecodeLimits.MAX_WIDTH}x${VideoDecodeLimits.MAX_HEIGHT}")
        }.onFailure { android.util.Log.w("PJSIP", "video codec $codecId param failed", it) }
    }

    internal fun applyCodecPriorities(applier: CodecPriorityApplier) {
        CodecPriorities.ordered.forEach { (codec, priority) -> applier.setPriority(codec, priority) }
    }

    fun endpointInstance(): Endpoint = endpoint

    /**
     * D-09/RESEARCH.md Pattern 3: called only after the platform reports a
     * new network with a usable IP (never on old-interface teardown).
     * restartListener + shutdownTransport mirror the exact IpChangeParam
     * shape documented at docs.pjsip.org/.../ip_change.html.
     */
    override fun handleIpChange() {
        if (!started) return
        // Keep the CPU up while PJSIP restarts the transport and re-registers (auto-released).
        de.haphone.app.test.ShortWakeLock.acquire(de.haphone.app.test.ShortWakeLock.NETWORK_CHANGE)
        val param = org.pjsip.pjsua2.IpChangeParam()
        param.restartListener = true
        param.shutdownTransport = true
        endpoint.handleIpChange(param)
    }

    /**
     * Real PJSUA2-backed [SipCallOperations] implementation (Task 3 wires
     * this into SipCallController), mirroring iOS's PjsuaBridge.mm
     * Account/Call wiring: register/unregister via a PJSUA2 Account,
     * makeCall/answer/hold/xfer/sendDtmf via a PJSUA2 Call, mute via
     * AudioMedia.adjustTxLevel (never AudioManager, per D-11).
     *
     * `username`/`password`/`domain` MUST be the literal real values
     * substituted by HAPhoneTestApplication from Plan 01's checkpoint
     * output -- see Task 3's HAPhoneTestApplication.kt edit.
     *
     * NOTE: exact PJSUA2 Java/Kotlin SWIG binding method/enum names
     * (e.g. `AudioMedia.typecastFromMedia`, `pjsua_call_flag`) mirror the
     * official pjsua2 Android sample cited in STACK.md
     * (kotlin-sip-client.html) -- verify each against this project's
     * generated bindings at build time, same as any other
     * SWIG-generated API surface.
     */
    /**
     * Points PJSIP at the PBX's STUN server (see [StunServer]). Non-blocking; a PBX without
     * STUN (older than 0.7.115) just fails the check and media falls back to the local address.
     */
    private fun useStunServer(domain: String) {
        val server = StunServer.forDomain(domain) ?: return
        try {
            val servers = org.pjsip.pjsua2.StringVector()
            servers.add(server)
            endpoint.natUpdateStunServers(servers, false)
        } catch (e: Exception) {
            android.util.Log.w("PJSIP", "STUN server $server not set: ${e.message}")
        }
    }

    fun asSipCallOperations(username: String, password: String, domain: String): SipCallOperations =
        object : SipCallOperations {
            private var account: HAPhoneAccount? = null

            override fun register() {
                val existing = account
                if (existing != null) {
                    if (existing.isValid) return
                    android.util.Log.w("PJSIP", "account became invalid, recreating")
                    synchronized(existing.lock) {
                        existing.activeCall = null
                        existing.otherCall = null
                    }
                    account = null
                    existing.delete()
                }
                useStunServer(domain)
                val cfg = org.pjsip.pjsua2.AccountConfig()
                cfg.idUri = "sip:$username@$domain"
                // STUN for media only: SIP runs over TLS, and the PBX fixes the Contact itself
                // (rewrite_contact). The SDP needs the reachable address for early-media video.
                cfg.natConfig.sipStunUse = org.pjsip.pjsua2.pjsua_stun_use.PJSUA_STUN_USE_DISABLED
                cfg.natConfig.mediaStunUse = org.pjsip.pjsua2.pjsua_stun_use.PJSUA_STUN_USE_DEFAULT
                // Without ;transport=tls PJSIP resolves the registrar to UDP, for which no transport exists.
                cfg.regConfig.registrarUri = "sip:$domain;transport=tls"
                // After a PBX restart / add-on update, come back within seconds, not after the
                // default 5 minutes (first retry fast, then every 30 s).
                cfg.regConfig.firstRetryIntervalSec = 5
                cfg.regConfig.retryIntervalSec = 30
                // Explicit, shorter than Asterisk's default 3600 s: PJSIP's own refresh timer
                // freezes in Doze, so ReachabilityMonitor's alarm re-REGISTERs ~120 s before
                // this runs out; a lost refresh then costs minutes of unreachability, not an hour.
                cfg.regConfig.timeoutSec = de.haphone.app.test.reach.ReachPolicy.REGISTRATION_EXPIRES_SEC.toLong()
                // TLS keep-alive: PJSIP sends CRLFCRLF every PJSIP_TLS_KEEP_ALIVE_INTERVAL (90 s,
                // compiled in; not settable through pjsua2) on an idle connection, and the PBX
                // qualifies every 60 s. sipOutboundUse (RFC 5626, default on) keeps inbound
                // requests on this same connection.
                cfg.natConfig.sipOutboundUse = 1
                val cred = org.pjsip.pjsua2.AuthCredInfo("digest", "*", username, 0, password)
                cfg.sipConfig.authCreds.add(cred)
                // DEV-ONLY (RESEARCH.md Pitfall 5): self-signed cert for the
                // Phase 2 TLS test transport, scoped to local-network-only
                // dev testing per D-05. Remove before a later
                // production-transport phase (Phase 5) without
                // re-evaluating cert trust.
                cfg.mediaConfig.transportConfig.tlsConfig.verifyServer = false
                // OPTIONAL, not MANDATORY: extensions default to media_encryption=none, which would 488 a mandatory-SRTP offer.
                cfg.mediaConfig.srtpUse = org.pjsip.pjsua2.pjmedia_srtp_use.PJMEDIA_SRTP_OPTIONAL
                cfg.mediaConfig.srtpSecureSignaling = 1 // T-2-10: SDES keys never sent unencrypted
                // No UPDATE right after answer just to narrow a multi-codec answer to one codec:
                // it adds a second offer/answer round the PBX does not need.
                cfg.mediaConfig.lockCodecEnabled = false
                // Receive-only video: show incoming door-station video, never send our camera.
                cfg.videoConfig.autoShowIncoming = true
                cfg.videoConfig.autoTransmitOutgoing = false
                val acc = HAPhoneAccount()
                acc.create(cfg)
                account = acc
            }

            override fun renewRegistration() {
                val acc = account
                if (acc == null || !acc.isValid) {
                    register()
                    return
                }
                // renew=true sends a fresh REGISTER (and reconnects TLS if the connection died).
                acc.setRegistration(true)
            }

            override fun unregister() {
                val acc = account ?: return
                account = null
                acc.shutdown()
                // Free the native object NOW. Account::shutdown() keeps the stale id, and
                // pjsua reuses ids: if the GC later finalizes this object, ~Account() ->
                // shutdown() -> isValid(id) is true again for the NEXT account and deletes it.
                acc.delete()
            }

            override fun makeCall(uri: String): Int {
                val acc = account ?: return -1
                val call = HAPhoneCall(acc)
                // Take the slot BEFORE the INVITE goes out, so an INVITE arriving on the PJSIP
                // worker meanwhile sees it occupied (and becomes call waiting / 486).
                val current = synchronized(acc.lock) {
                    val running = acc.activeCall
                    if (running != null && acc.otherCall != null) null
                    else {
                        if (running != null) acc.otherCall = running
                        acc.activeCall = call
                        acc.conference = false
                        running ?: call
                    }
                }
                if (current == null) {
                    call.delete()
                    error("Schon zwei Gespräche aktiv")
                }
                val held = current.takeIf { it !== call }
                try {
                    // Consultation call: the running call waits on hold behind the new one.
                    held?.let { holdCall(it) }
                    val prm = org.pjsip.pjsua2.CallOpParam(true)
                    prm.opt.videoCount = 0
                    call.makeCall(uri, prm)
                } catch (e: Exception) {
                    synchronized(acc.lock) {
                        if (acc.activeCall === call) {
                            acc.activeCall = held
                            if (acc.otherCall === held) acc.otherCall = null
                        }
                    }
                    held?.let { h -> runCatching { unholdCall(h) } }
                    call.delete()
                    throw e
                }
                return call.id
            }

            override fun answerWaiting(): Boolean {
                val acc = account ?: return false
                val waiting = acc.otherCall ?: return false
                // Only a call that is still knocking: it may have been cancelled a moment ago.
                if (!waiting.isStillRinging()) {
                    android.util.Log.i("PJSIP", "answerWaiting: waiting call is no longer ringing")
                    return false
                }
                val current = acc.activeCall
                current?.let { holdCall(it) }
                val prm = org.pjsip.pjsua2.CallOpParam(true)
                prm.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_OK
                try {
                    waiting.answer(prm)
                } catch (e: Exception) {
                    // Keep the running call as it was: back from hold, still on screen.
                    current?.let { c -> runCatching { unholdCall(c) } }
                    throw e
                }
                // Swap only after the 200 OK went out.
                synchronized(acc.lock) {
                    if (acc.otherCall === waiting) {
                        acc.otherCall = acc.activeCall
                        acc.activeCall = waiting
                        acc.conference = false
                    }
                }
                return true
            }

            override fun rejectWaiting() {
                val waiting = account?.otherCall ?: return
                val prm = org.pjsip.pjsua2.CallOpParam()
                prm.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_BUSY_HERE
                waiting.hangup(prm)
            }

            override fun swap(): Boolean {
                val acc = account ?: return false
                val current = acc.activeCall ?: return false
                val held = acc.otherCall ?: return false
                holdCall(current)
                unholdCall(held)
                synchronized(acc.lock) {
                    acc.activeCall = held
                    acc.otherCall = current
                    acc.conference = false
                }
                return true
            }

            override fun merge(): Boolean {
                val acc = account ?: return false
                val current = acc.activeCall ?: return false
                val held = acc.otherCall ?: return false
                acc.conference = true
                unholdCall(held)
                // Both legs may already have active media; bridge now, and again from
                // onCallMediaState once the unhold re-INVITE brings the held leg back.
                current.bridgeConference()
                return true
            }

            override fun transferAttended(): Boolean {
                val acc = account ?: return false
                val current = acc.activeCall ?: return false
                val held = acc.otherCall ?: return false
                // REFER to the held party with Replaces=<current dialog>: it takes over our
                // leg to the consulted party, then the PBX ends both of our calls.
                held.xferReplaces(current, org.pjsip.pjsua2.CallOpParam(true))
                return true
            }

            override fun answer(): Boolean {
                val call = account?.activeCall ?: return false
                return answerCall(call)
            }

            override fun answer(callId: Int): Boolean {
                // Only the call on screen: a waiting call is taken via answerWaiting (holds the other).
                val call = account?.activeCall?.takeIf { it.id == callId } ?: return false
                return answerCall(call)
            }

            private fun answerCall(call: HAPhoneCall): Boolean {
                val prm = org.pjsip.pjsua2.CallOpParam(true)
                prm.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_OK
                call.answer(prm)
                return call.lastAnswerSucceeded
            }

            override fun hold(onHold: Boolean) {
                val call = account?.activeCall ?: return
                if (onHold) holdCall(call) else unholdCall(call)
            }

            private fun holdCall(call: HAPhoneCall) {
                call.setHold(org.pjsip.pjsua2.CallOpParam())
            }

            private fun unholdCall(call: HAPhoneCall) {
                val prm = org.pjsip.pjsua2.CallOpParam()
                // NOTE (Rule 1 fix): this project's SWIG 4.2.0-generated bindings
                // expose pjsua_call_flag as plain `int` constants (no enum type,
                // no .swigValue()) -- CallSetting.flag is a `long` setter.
                prm.opt.flag = org.pjsip.pjsua2.pjsua_call_flag.PJSUA_CALL_UNHOLD.toLong()
                call.reinvite(prm)
            }

            override fun mute(muted: Boolean) {
                // Mute at the PJSUA2 media level (AudioMedia.adjustTxLevel),
                // never AudioManager -- matches D-11/RESEARCH.md Pattern 2's
                // "OS owns routing, PJSIP owns media" split.
                val call = account?.activeCall ?: return
                val info = call.getInfo()
                for (media in info.media) {
                    if (media.type == org.pjsip.pjsua2.pjmedia_type.PJMEDIA_TYPE_AUDIO &&
                        media.status == org.pjsip.pjsua2.pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE
                    ) {
                        val audioMedia = org.pjsip.pjsua2.AudioMedia.typecastFromMedia(call.getMedia(media.index))
                        audioMedia.adjustTxLevel(if (muted) 0.0f else 1.0f)
                    }
                }
            }

            override fun transfer(uri: String) {
                val call = account?.activeCall ?: return
                call.xfer(uri, org.pjsip.pjsua2.CallOpParam())
            }

            override fun queueDtmfOnConnect(digits: String) {
                account?.pendingDtmf = digits
            }

            override fun sendDtmf(digit: String) {
                val call = account?.activeCall ?: return
                val dtmfParam = org.pjsip.pjsua2.CallSendDtmfParam()
                dtmfParam.method = org.pjsip.pjsua2.pjsua_dtmf_method.PJSUA_DTMF_METHOD_RFC2833
                dtmfParam.digits = digit
                call.sendDtmf(dtmfParam)
            }

            override fun hangup() {
                val call = account?.activeCall ?: return
                hangupCall(call)
            }

            override fun hangup(callId: Int) {
                val acc = account ?: return
                val call = listOfNotNull(acc.activeCall, acc.otherCall).firstOrNull { it.id == callId } ?: return
                hangupCall(call)
            }

            private fun hangupCall(call: HAPhoneCall) {
                // The slot is cleared by the DISCONNECTED callback; only clear it here if
                // hangup throws (e.g. the session had already terminated).
                try {
                    call.hangup(org.pjsip.pjsua2.CallOpParam())
                } catch (e: Exception) {
                    account?.let { acc ->
                        synchronized(acc.lock) {
                            if (acc.activeCall === call) {
                                acc.activeCall = acc.otherCall
                                acc.otherCall = null
                            } else if (acc.otherCall === call) {
                                acc.otherCall = null
                            }
                        }
                    }
                    throw e
                }
            }
        }
}

/**
 * Account subclass holding the single active Call for this app (mirrors
 * PjsuaBridge.mm's HAPhoneAccount).
 */
private class HAPhoneAccount : org.pjsip.pjsua2.Account() {
    /**
     * Guards [activeCall]/[otherCall]/[conference]: [onIncomingCall] and the DISCONNECTED
     * branch of HAPhoneCall.onCallState run on the PJSIP worker, everything else on main.
     * Held only for field reads/writes, NEVER around a PJSIP call (the worker holds PJSIP's
     * own locks while it waits for this one -> deadlock).
     */
    val lock = Any()
    /** The call on screen. */
    @Volatile var activeCall: HAPhoneCall? = null
    /** Second call: on hold behind [activeCall], or ringing as call waiting. */
    @Volatile var otherCall: HAPhoneCall? = null
    /** Both calls are mixed together (3-way conference in our own audio bridge). */
    @Volatile var conference = false
    /** DTMF to send once the active call is answered (e.g. "Tür öffnen" from the ringing screen). */
    @Volatile var pendingDtmf: String? = null
    /** Calls rejected by the ring policy, held until their DISCONNECTED callback frees them. */
    val rejectedCalls = java.util.Collections.synchronizedSet(mutableSetOf<HAPhoneCall>())

    override fun onRegState(prm: org.pjsip.pjsua2.OnRegStateParam) {
        val code = prm.code
        val expiration = prm.expiration
        val reason = runCatching { prm.reason }.getOrDefault("")
        val policy = de.haphone.app.test.reach.ReachPolicy
        val state = with(policy) { classifyRegState(code, expiration).channelName() }
        android.util.Log.i("PJSIP", "onRegState code=$code reason=$reason expires=$expiration")
        de.haphone.app.test.CallEventBus.emitRegistrationState(state, code)
        // Worker thread -> main: reschedule the Doze alarm and release the attempt's wake lock.
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            de.haphone.app.test.reach.ReachabilityMonitor.onRegState(code, expiration, reason)
        }
    }

    /**
     * Blocker fix (checker iteration 4): mandatory PJSUA2 pattern present
     * in every official pjsua2 sample -- without this override, PJSUA2
     * has no C++-level handle on an inbound SIP INVITE at all, and
     * `activeCall` stays permanently null for every incoming call (it
     * was previously populated ONLY by makeCall()'s outgoing path).
     * Constructs the incoming Call wrapper from the callback's call-id
     * and stores it as `activeCall` BEFORE any
     * answer()/hold()/mute()/transfer()/sendDtmf() path can succeed --
     * this is the missing link that makes inbound calls answerable at
     * all. The real 200 OK answer still only happens from
     * CallRegistration's real onAnswer callback (gated on Telecom's
     * genuine user-answer signal, not here) -- this override only sends
     * a provisional 180 Ringing so the caller's device shows ringing in
     * the meantime.
     */
    override fun onIncomingCall(prm: org.pjsip.pjsua2.OnIncomingCallParam) {
        // Doze: keep the CPU up until the ringing UI / notification is posted on main.
        de.haphone.app.test.ShortWakeLock.acquire(de.haphone.app.test.ShortWakeLock.INCOMING_CALL)
        val call = HAPhoneCall(this, prm.callId)
        // "Klingeln auf diesem Handy" off / muted: 480 before any ringing UI or Telecom,
        // so ring groups go on to the other devices and direct calls reach the PBX fallback.
        val offersVideo = runCatching { prm.rdata.wholeMsg.contains("m=video") }.getOrDefault(false)
        val caller = parseRemoteUri(runCatching { call.info.remoteUri }.getOrDefault("")).first
        val decision = de.haphone.app.test.ring.RingPolicyStore.decide(caller, offersVideo)
        if (with(de.haphone.app.test.ring.RingPolicy) { decision.rejects() }) {
            val unavailable = org.pjsip.pjsua2.CallOpParam()
            unavailable.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_TEMPORARILY_UNAVAILABLE
            // Keep a reference until DISCONNECTED (which deletes it), or the GC could free it early.
            rejectedCalls.add(call)
            runCatching { call.hangup(unavailable) }
                .onFailure { android.util.Log.w(de.haphone.app.test.ring.RingPolicyStore.TAG, "480 reply failed", it) }
            android.util.Log.i(de.haphone.app.test.ring.RingPolicyStore.TAG, "rejected call ${prm.callId} from $caller with 480 ($decision)")
            de.haphone.app.test.ShortWakeLock.release(de.haphone.app.test.ShortWakeLock.INCOMING_CALL)
            return
        }
        // Classified under the lock: the previous call's DISCONNECTED clears its slot on this
        // same worker thread (synchronously), so a call arriving right after a hangup is not
        // mistaken for call waiting, and main cannot change the slots halfway.
        val waiting: Boolean? = synchronized(lock) {
            when {
                activeCall != null && otherCall != null -> null
                activeCall != null -> { otherCall = call; true }
                else -> { activeCall = call; false }
            }
        }
        if (waiting == null) {
            val busy = org.pjsip.pjsua2.CallOpParam()
            busy.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_BUSY_HERE
            // Keep a reference until DISCONNECTED (which deletes it), or the GC could free it early.
            rejectedCalls.add(call)
            runCatching { call.hangup(busy) }
                .onFailure { android.util.Log.w("PJSIP", "486 reply failed", it) }
            de.haphone.app.test.ShortWakeLock.release(de.haphone.app.test.ShortWakeLock.INCOMING_CALL)
            return
        }
        // No early media for a waiting call: its video would take the window of the running call.
        val hasVideo = !waiting && runCatching { prm.rdata.wholeMsg.contains("m=video") }.getOrDefault(false)
        val (number, name) = parseRemoteUri(runCatching { call.info.remoteUri }.getOrDefault(""))
        val reply = org.pjsip.pjsua2.CallOpParam()
        if (hasVideo) {
            // 183 + SDP = early media: the PBX starts passing the door station's
            // video before anyone answers. Audio is not connected to mic/speaker
            // until CONFIRMED (see HAPhoneCall.connectAudio).
            reply.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_PROGRESS
            reply.opt.audioCount = 1
            reply.opt.videoCount = 1
        } else {
            // Plain 180 for normal calls: a 183 with (silent) media would replace the
            // caller's ringback tone with silence.
            reply.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_RINGING
        }
        // An exception must not escape into the PJSIP callback; the call can still be answered with 200.
        runCatching { call.answer(reply) }
            .onFailure { android.util.Log.w("PJSIP", "provisional ${reply.statusCode} reply failed", it) }
        android.util.Log.i("PJSIP", "incoming call from $number ($name) video=$hasVideo waiting=$waiting")
        val callId = prm.callId
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try {
                SipCallEvents.onIncomingCall?.invoke(IncomingSipCall(callId, number, name, hasVideo, waiting))
            } finally {
                de.haphone.app.test.ShortWakeLock.release(de.haphone.app.test.ShortWakeLock.INCOMING_CALL)
            }
        }
    }
}

/** Call subclass tracking whether the last SIP negotiation actually succeeded (mirrors PjsuaBridge.mm's HAPhoneCall). */
private class HAPhoneCall(
    private val owner: HAPhoneAccount,
    callId: Int = -1, // PJSUA_INVALID_ID -- outgoing calls (makeCall) omit this and let PJSUA2 assign a fresh id; onIncomingCall (above) passes the real inbound call-id.
) : org.pjsip.pjsua2.Call(owner, callId) {
    var lastAnswerSucceeded: Boolean = true

    /** INCOMING/EARLY: not answered, not ended (call waiting may have been cancelled meanwhile). */
    fun isStillRinging(): Boolean = runCatching {
        val state = getInfo().state
        state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_INCOMING ||
            state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_EARLY
    }.getOrDefault(false)

    /** Set once CONFIRMED: before that (early media) mic and speaker stay disconnected. */
    private var answered = false

    private fun activeAudio(): org.pjsip.pjsua2.AudioMedia? {
        val info = getInfo()
        for (i in 0 until info.media.size) {
            val m = info.media[i]
            if (m.type == org.pjsip.pjsua2.pjmedia_type.PJMEDIA_TYPE_AUDIO &&
                m.status == org.pjsip.pjsua2.pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE
            ) return getAudioMedia(i)
        }
        return null
    }

    /**
     * Wires mic/speaker to this call. Re-run on every media change: after hold/unhold
     * (swap, conference) the audio port has to be connected again; repeat connects are no-ops.
     */
    private fun connectAudio() {
        if (!answered) return
        val am = activeAudio() ?: return
        val adm = org.pjsip.pjsua2.Endpoint.instance().audDevManager()
        adm.captureDevMedia.startTransmit(am)
        am.startTransmit(adm.playbackDevMedia)
        if (owner.conference) bridgeConference()
    }

    /** 3-way conference: both remote parties hear each other, we hear and speak to both. */
    fun bridgeConference() {
        val first = owner.activeCall?.activeAudio() ?: return
        val second = owner.otherCall?.activeAudio() ?: return
        runCatching {
            first.startTransmit(second)
            second.startTransmit(first)
        }.onFailure { android.util.Log.w("PJSIP", "conference bridge failed", it) }
    }

    override fun onCallMediaState(prm: org.pjsip.pjsua2.OnCallMediaStateParam) {
        val info = getInfo()
        for (i in 0 until info.media.size) {
            val m = info.media[i]
            if (m.type == org.pjsip.pjsua2.pjmedia_type.PJMEDIA_TYPE_VIDEO &&
                m.status == org.pjsip.pjsua2.pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE &&
                m.videoIncomingWindowId >= 0 &&
                owner.activeCall === this
            ) {
                val windowId = m.videoIncomingWindowId
                android.util.Log.i("PJSIP", "incoming video window $windowId")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    VideoSurfaceBinder.setWindowId(windowId)
                }
            }
        }
        connectAudio()
    }

    private fun sendPendingDtmf() {
        val digits = owner.pendingDtmf ?: return
        if (owner.activeCall !== this) return
        owner.pendingDtmf = null
        runCatching {
            val p = org.pjsip.pjsua2.CallSendDtmfParam()
            p.method = org.pjsip.pjsua2.pjsua_dtmf_method.PJSUA_DTMF_METHOD_RFC2833
            p.digits = digits
            sendDtmf(p)
        }.onFailure { android.util.Log.w("PJSIP", "pending DTMF failed", it) }
    }

    /** End our leg once a (blind or attended) transfer is accepted: the PBX has taken over. */
    override fun onCallTransferStatus(prm: org.pjsip.pjsua2.OnCallTransferStatusParam) {
        android.util.Log.i("PJSIP", "transfer status ${prm.statusCode} final=${prm.finalNotify}")
        if (prm.finalNotify && prm.statusCode / 100 == 2) prm.cont = false
    }

    override fun onCallState(prm: org.pjsip.pjsua2.OnCallStateParam) {
        val info = getInfo()
        val myId = info.id
        val ringback = de.haphone.app.test.calls.Ringback.actionFor(
            isCallOnScreen = owner.activeCall === this,
            isOutgoing = info.role == org.pjsip.pjsua2.pjsip_role_e.PJSIP_ROLE_UAC,
            isEarly = info.state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_EARLY,
        )
        if (ringback != null) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                when (ringback) {
                    de.haphone.app.test.calls.Ringback.Action.START -> de.haphone.app.test.calls.Ringback.start()
                    de.haphone.app.test.calls.Ringback.Action.STOP -> de.haphone.app.test.calls.Ringback.stop()
                }
            }
        }
        if (info.state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_CONFIRMED) {
            answered = true
            // Media may already have gone active during early media (183), in which
            // case onCallMediaState won't fire again on answer.
            connectAudio()
            val main = android.os.Handler(android.os.Looper.getMainLooper())
            main.post { SipCallEvents.onCallConfirmed?.invoke(myId) }
            // Door stations ignore DTMF sent before their own media is up; give them a moment.
            main.postDelayed({ sendPendingDtmf() }, PENDING_DTMF_DELAY_MS)
        }
        if (info.state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_DISCONNECTED) {
            // NOTE (Rule 1 fix): CallInfo.lastStatusCode is a plain `int` getter in
            // this project's SWIG 4.2.0 bindings (pjsip_status_code has no enum
            // type/.swigValue()) -- compare directly.
            lastAnswerSucceeded = info.lastStatusCode < 400
            val reason = "${info.lastStatusCode} ${info.lastReason}"
            android.util.Log.i("PJSIP", "call $myId disconnected: $reason")
            // Free the slot right here on the worker (under the lock), so an INVITE that arrives
            // before main has run is classified against the real state (see onIncomingCall).
            val (wasActive, wasOther) = synchronized(owner.lock) {
                val active = owner.activeCall === this
                val other = owner.otherCall === this
                if (active) {
                    owner.activeCall = owner.otherCall
                    owner.otherCall = null
                    owner.pendingDtmf = null
                } else if (other) {
                    owner.otherCall = null
                }
                if (active || other) owner.conference = false
                active to other
            }
            // Telecom, UI and delete() only on main.
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                owner.rejectedCalls.remove(this)
                if (wasActive || wasOther) {
                    SipCallEvents.onCallDisconnected?.invoke(myId, reason)
                }
                // Free now, not at GC time: ~Call() hangs up whatever call currently
                // holds this (reused) call id, which would kill a later, unrelated call.
                delete()
            }
        }
    }

    private companion object {
        const val PENDING_DTMF_DELAY_MS = 800L
    }
}
