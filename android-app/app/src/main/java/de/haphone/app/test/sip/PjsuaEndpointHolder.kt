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
class PjsuaEndpointHolder : IpChangeNotifier {
    private val endpoint = Endpoint()
    private var started = false

    fun start() {
        if (started) return
        endpoint.libCreate()
        val epConfig = EpConfig()
        endpoint.libInit(epConfig)
        endpoint.libStart()
        applyCodecPriorities(object : CodecPriorityApplier {
            override fun setPriority(codecId: String, priority: Int) {
                endpoint.codecSetPriority(codecId, priority.toShort())
            }
        })
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
                val cfg = org.pjsip.pjsua2.AccountConfig()
                cfg.idUri = "sip:$username@$domain"
                cfg.regConfig.registrarUri = "sip:$domain"
                val cred = org.pjsip.pjsua2.AuthCredInfo("digest", "*", username, 0, password)
                cfg.sipConfig.authCreds.add(cred)
                // DEV-ONLY (RESEARCH.md Pitfall 5): self-signed cert for the
                // Phase 2 TLS test transport, scoped to local-network-only
                // dev testing per D-05. Remove before a later
                // production-transport phase (Phase 5) without
                // re-evaluating cert trust.
                cfg.mediaConfig.transportConfig.tlsConfig.verifyServer = false
                cfg.mediaConfig.srtpUse = org.pjsip.pjsua2.pjmedia_srtp_use.PJMEDIA_SRTP_MANDATORY
                cfg.mediaConfig.srtpSecureSignaling = 1 // T-2-10: SDES keys never sent unencrypted
                val acc = HAPhoneAccount()
                acc.create(cfg)
                account = acc
            }

            override fun unregister() {
                account?.shutdown()
                account = null
            }

            override fun makeCall(uri: String) {
                val acc = account ?: return
                val call = HAPhoneCall(acc)
                val prm = org.pjsip.pjsua2.CallOpParam(true)
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

            override fun sendDtmf(digit: String) {
                val call = account?.activeCall ?: return
                val dtmfParam = org.pjsip.pjsua2.CallSendDtmfParam()
                dtmfParam.method = org.pjsip.pjsua2.pjsua_dtmf_method.PJSUA_DTMF_METHOD_RFC2833
                dtmfParam.digits = digit
                call.sendDtmf(dtmfParam)
            }

            override fun hangup() {
                val call = account?.activeCall ?: return
                call.hangup(org.pjsip.pjsua2.CallOpParam())
                account?.activeCall = null
            }
        }
}

/**
 * Account subclass holding the single active Call for this app (mirrors
 * PjsuaBridge.mm's HAPhoneAccount).
 */
private class HAPhoneAccount : org.pjsip.pjsua2.Account() {
    var activeCall: HAPhoneCall? = null

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
        activeCall = call
        val ringing = org.pjsip.pjsua2.CallOpParam()
        ringing.statusCode = org.pjsip.pjsua2.pjsip_status_code.PJSIP_SC_RINGING
        call.answer(ringing)
    }
}

/** Call subclass tracking whether the last SIP negotiation actually succeeded (mirrors PjsuaBridge.mm's HAPhoneCall). */
private class HAPhoneCall(
    acc: org.pjsip.pjsua2.Account,
    callId: Int = -1, // PJSUA_INVALID_ID -- outgoing calls (makeCall) omit this and let PJSUA2 assign a fresh id; onIncomingCall (above) passes the real inbound call-id.
) : org.pjsip.pjsua2.Call(acc, callId) {
    var lastAnswerSucceeded: Boolean = true

    override fun onCallState(prm: org.pjsip.pjsua2.OnCallStateParam) {
        val info = getInfo()
        if (info.state == org.pjsip.pjsua2.pjsip_inv_state.PJSIP_INV_STATE_DISCONNECTED) {
            // NOTE (Rule 1 fix): CallInfo.lastStatusCode is a plain `int` getter in
            // this project's SWIG 4.2.0 bindings (pjsip_status_code has no enum
            // type/.swigValue()) -- compare directly.
            lastAnswerSucceeded = info.lastStatusCode < 400
        }
    }
}
