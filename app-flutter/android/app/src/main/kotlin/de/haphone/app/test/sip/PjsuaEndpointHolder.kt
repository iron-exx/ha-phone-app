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
data class IncomingSipCall(val number: String, val displayName: String, val hasVideo: Boolean)

/** Main-thread notifications from the PJSIP layer. */
object SipCallEvents {
    /** The current SIP call ended (remote hangup/cancel, failure, or local hangup). */
    var onCallDisconnected: ((reason: String) -> Unit)? = null
    /** A new SIP INVITE is ringing (already answered with 180, or 183 early media for video). */
    var onIncomingCall: ((IncomingSipCall) -> Unit)? = null
    /** The current call was answered (SIP CONFIRMED). */
    var onCallConfirmed: (() -> Unit)? = null
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

class PjsuaEndpointHolder : IpChangeNotifier {
    private val endpoint = Endpoint()
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
            }
        }.onFailure { android.util.Log.w("PJSIP", "video codec setup failed", it) }
        started = true
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
    fun asSipCallOperations(username: String, password: String, domain: String): SipCallOperations =
        object : SipCallOperations {
            private var account: HAPhoneAccount? = null

            override fun register() {
                val existing = account
                if (existing != null) {
                    if (existing.isValid) return
                    android.util.Log.w("PJSIP", "account became invalid, recreating")
                    existing.activeCall = null
                    account = null
                    existing.delete()
                }
                val cfg = org.pjsip.pjsua2.AccountConfig()
                cfg.idUri = "sip:$username@$domain"
                // Without ;transport=tls PJSIP resolves the registrar to UDP, for which no transport exists.
                cfg.regConfig.registrarUri = "sip:$domain;transport=tls"
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

            override fun unregister() {
                val acc = account ?: return
                account = null
                acc.shutdown()
                // Free the native object NOW. Account::shutdown() keeps the stale id, and
                // pjsua reuses ids: if the GC later finalizes this object, ~Account() ->
                // shutdown() -> isValid(id) is true again for the NEXT account and deletes it.
                acc.delete()
            }

            override fun makeCall(uri: String) {
                val acc = account ?: return
                val call = HAPhoneCall(acc)
                val prm = org.pjsip.pjsua2.CallOpParam(true)
                prm.opt.videoCount = 0
                call.makeCall(uri, prm)
                acc.activeCall = call
            }

            override fun answer(): Boolean {
                val call = account?.activeCall ?: return false
                val prm = org.pjsip.pjsua2.CallOpParam(true)
                prm.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_OK
                call.answer(prm)
                return call.lastAnswerSucceeded
            }

            override fun hold(onHold: Boolean) {
                val call = account?.activeCall ?: return
                if (onHold) {
                    call.setHold(org.pjsip.pjsua2.CallOpParam())
                } else {
                    val prm = org.pjsip.pjsua2.CallOpParam()
                    // NOTE (Rule 1 fix): this project's SWIG 4.2.0-generated bindings
                    // expose pjsua_call_flag as plain `int` constants (no enum type,
                    // no .swigValue()) -- CallSetting.flag is a `long` setter.
                    prm.opt.flag = org.pjsip.pjsua2.pjsua_call_flag.PJSUA_CALL_UNHOLD.toLong()
                    call.reinvite(prm)
                }
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
                // activeCall is cleared by the DISCONNECTED callback; only clear it here if
                // hangup throws (e.g. the session had already terminated).
                try {
                    call.hangup(org.pjsip.pjsua2.CallOpParam())
                } catch (e: Exception) {
                    if (account?.activeCall === call) account?.activeCall = null
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
    var activeCall: HAPhoneCall? = null
    /** DTMF to send once the active call is answered (e.g. "Tür öffnen" from the ringing screen). */
    var pendingDtmf: String? = null

    override fun onRegState(prm: org.pjsip.pjsua2.OnRegStateParam) {
        val code = prm.code
        val state = when {
            code / 100 == 2 && prm.expiration > 0 -> "registered"
            code / 100 == 2 -> "unregistered"
            else -> "failed"
        }
        android.util.Log.i("PJSIP", "onRegState code=$code reason=${prm.reason} expires=${prm.expiration}")
        de.haphone.app.test.CallEventBus.emitRegistrationState(state, code)
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
        val call = HAPhoneCall(this, prm.callId)
        if (activeCall != null) {
            val busy = org.pjsip.pjsua2.CallOpParam()
            busy.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_BUSY_HERE
            call.hangup(busy)
            return
        }
        activeCall = call
        val hasVideo = runCatching { prm.rdata.wholeMsg.contains("m=video") }.getOrDefault(false)
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
        call.answer(reply)
        android.util.Log.i("PJSIP", "incoming call from $number ($name) video=$hasVideo")
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            SipCallEvents.onIncomingCall?.invoke(IncomingSipCall(number, name, hasVideo))
        }
    }
}

/** Call subclass tracking whether the last SIP negotiation actually succeeded (mirrors PjsuaBridge.mm's HAPhoneCall). */
private class HAPhoneCall(
    private val owner: HAPhoneAccount,
    callId: Int = -1, // PJSUA_INVALID_ID -- outgoing calls (makeCall) omit this and let PJSUA2 assign a fresh id; onIncomingCall (above) passes the real inbound call-id.
) : org.pjsip.pjsua2.Call(owner, callId) {
    var lastAnswerSucceeded: Boolean = true

    private var audioConnected = false

    /** Mic/speaker are only wired up once the call is answered, never during early media. */
    private fun connectAudio(info: org.pjsip.pjsua2.CallInfo) {
        if (audioConnected) return
        val adm = org.pjsip.pjsua2.Endpoint.instance().audDevManager()
        for (i in 0 until info.media.size) {
            val m = info.media[i]
            if (m.type == org.pjsip.pjsua2.pjmedia_type.PJMEDIA_TYPE_AUDIO &&
                m.status == org.pjsip.pjsua2.pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE
            ) {
                val am = getAudioMedia(i)
                adm.captureDevMedia.startTransmit(am)
                am.startTransmit(adm.playbackDevMedia)
                audioConnected = true
            }
        }
    }

    override fun onCallMediaState(prm: org.pjsip.pjsua2.OnCallMediaStateParam) {
        val info = getInfo()
        for (i in 0 until info.media.size) {
            val m = info.media[i]
            if (m.type == org.pjsip.pjsua2.pjmedia_type.PJMEDIA_TYPE_VIDEO &&
                m.status == org.pjsip.pjsua2.pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE &&
                m.videoIncomingWindowId >= 0
            ) {
                val windowId = m.videoIncomingWindowId
                android.util.Log.i("PJSIP", "incoming video window $windowId")
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    VideoSurfaceBinder.setWindowId(windowId)
                }
            }
        }
        if (info.state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_CONFIRMED) connectAudio(info)
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

    override fun onCallState(prm: org.pjsip.pjsua2.OnCallStateParam) {
        val info = getInfo()
        if (info.state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_CONFIRMED) {
            // Media may already have gone active during early media (183), in which
            // case onCallMediaState won't fire again on answer.
            connectAudio(info)
            val main = android.os.Handler(android.os.Looper.getMainLooper())
            main.post { if (owner.activeCall === this) SipCallEvents.onCallConfirmed?.invoke() }
            // Door stations ignore DTMF sent before their own media is up; give them a moment.
            main.postDelayed({ sendPendingDtmf() }, PENDING_DTMF_DELAY_MS)
        }
        if (info.state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_DISCONNECTED) {
            // NOTE (Rule 1 fix): CallInfo.lastStatusCode is a plain `int` getter in
            // this project's SWIG 4.2.0 bindings (pjsip_status_code has no enum
            // type/.swigValue()) -- compare directly.
            lastAnswerSucceeded = info.lastStatusCode < 400
            val reason = "${info.lastStatusCode} ${info.lastReason}"
            android.util.Log.i("PJSIP", "call disconnected: $reason")
            // Arrives on the PJSIP worker thread; activeCall and Telecom are only touched on main.
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                // A rejected second call (486 while busy) must not end the current one.
                if (owner.activeCall === this) {
                    owner.activeCall = null
                    owner.pendingDtmf = null
                    SipCallEvents.onCallDisconnected?.invoke(reason)
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
