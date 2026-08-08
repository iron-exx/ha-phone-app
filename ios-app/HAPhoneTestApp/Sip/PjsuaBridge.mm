#import "PjsuaBridge.h"
#include <pjsua2.hpp>

using namespace pj;

// NOTE (RESEARCH.md Pitfall 1): PJSIP 2.17 changed Call::acc from
// Account& to Account* -- use -> not . when accessing it.

namespace {
class HAPhoneCall : public Call {
public:
    HAPhoneCall(Account &acc, int call_id = PJSUA_INVALID_ID) : Call(acc, call_id) {}
    bool lastAnswerSucceeded = true;
    void onCallState(OnCallStateParam &prm) override {
        CallInfo ci = getInfo();
        if (ci.state == PJSIP_INV_STATE_DISCONNECTED) {
            lastAnswerSucceeded = (ci.lastStatusCode < 400);
        }
    }
};

class HAPhoneAccount : public Account {
public:
    std::unique_ptr<HAPhoneCall> activeCall;

    // Blocker fix (checker iteration 4): mandatory PJSUA2 pattern
    // present in every official pjsua2 sample -- without this override,
    // PJSUA2 has no C++-level handle on an inbound SIP INVITE at all,
    // and activeCall stays permanently null for every incoming call
    // (it was previously populated ONLY by makeCallWithUri:'s outgoing
    // path). Constructs the incoming Call wrapper from the callback's
    // call-id and stores it as activeCall BEFORE any
    // answerCall/setHold/setMuted/transferToUri/sendDtmf path can
    // succeed -- this is the missing link that makes inbound calls
    // answerable at all. The real 200 OK answer still only happens
    // from CXAnswerCallAction's handler in CallProvider.swift (gated
    // on CallKit's genuine user-answer signal, not here) -- this
    // override only sends a provisional 180 Ringing so the caller's
    // device shows ringing in the meantime.
    virtual void onIncomingCall(OnIncomingCallParam &prm) override {
        activeCall = std::make_unique<HAPhoneCall>(*this, prm.callId);
        CallOpParam ringingPrm;
        ringingPrm.statusCode = PJSIP_SC_RINGING;
        activeCall->answer(ringingPrm);
    }
};
}  // namespace

@implementation PjsuaBridge {
    Endpoint _endpoint;
    std::unique_ptr<HAPhoneAccount> _account;
}

- (void)start {
    _endpoint.libCreate();
    EpConfig epConfig;
    _endpoint.libInit(epConfig);
    _endpoint.libStart();
    // CALL-01/D-07: all 3 codecs verified for real.
    _endpoint.codecSetPriority("opus/48000", 255);
    _endpoint.codecSetPriority("g722/16000", 200);
    _endpoint.codecSetPriority("pcma/8000", 150);
    _endpoint.codecSetPriority("pcmu/8000", 150);
}

- (void)registerAccountWithDomain:(NSString *)domain username:(NSString *)username password:(NSString *)password {
    AccountConfig accCfg;
    accCfg.idUri = [[NSString stringWithFormat:@"sip:%@@%@", username, domain] UTF8String];
    accCfg.regConfig.registrarUri = [[NSString stringWithFormat:@"sip:%@", domain] UTF8String];
    AuthCredInfo cred("digest", "*", [username UTF8String], 0, [password UTF8String]);
    accCfg.sipConfig.authCreds.push_back(cred);
    // DEV-ONLY (RESEARCH.md Pitfall 5): self-signed cert for the Phase 2
    // TLS test transport, scoped to local-network-only dev testing per
    // D-05. Do NOT carry this into a later production-transport phase
    // without re-evaluating cert trust.
    accCfg.mediaConfig.transportConfig.tlsConfig.verifyServer = false;
    accCfg.mediaConfig.srtpUse = PJMEDIA_SRTP_MANDATORY;
    accCfg.mediaConfig.srtpSecureSignaling = 1; // T-2-10: SDES keys never sent unencrypted
    _account = std::make_unique<HAPhoneAccount>();
    _account->create(accCfg);
}

- (void)unregisterAccount {
    if (_account) {
        _account->shutdown();
        _account.reset();
    }
}

- (void)makeCallWithUri:(NSString *)uri {
    if (!_account) return;
    CallOpParam prm(true);
    _account->activeCall = std::make_unique<HAPhoneCall>(*_account);
    _account->activeCall->makeCall([uri UTF8String], prm);
}

- (BOOL)answerCall {
    if (!_account || !_account->activeCall) return NO;
    CallOpParam prm(true);
    prm.statusCode = PJSIP_SC_OK;
    _account->activeCall->answer(prm);
    return _account->activeCall->lastAnswerSucceeded;
}

- (void)setHold:(BOOL)onHold {
    if (!_account || !_account->activeCall) return;
    CallOpParam prm;
    if (onHold) {
        _account->activeCall->setHold(prm);
    } else {
        prm.opt.flag = PJSUA_CALL_UNHOLD;
        _account->activeCall->reinvite(prm);
    }
}

- (void)setMuted:(BOOL)muted {
    // Mute at the PJSUA2 media level (AudioMedia.adjustTxLevel), not via
    // AVAudioSession -- keeps mute entirely within PJSIP's own media
    // graph, consistent with RESEARCH.md Pattern 2's "OS owns routing,
    // PJSIP owns media" split (mute is a media-transmit concern, not a
    // route-selection concern).
    if (!_account || !_account->activeCall) return;
    CallInfo ci = _account->activeCall->getInfo();
    for (const CallMediaInfo &mi : ci.media) {
        if (mi.type == PJMEDIA_TYPE_AUDIO && mi.status == PJSUA_CALL_MEDIA_ACTIVE) {
            AudioMedia am = _account->activeCall->getAudioMedia(mi.index);
            am.adjustTxLevel(muted ? 0.0f : 1.0f);
        }
    }
}

- (void)transferToUri:(NSString *)uri {
    if (!_account || !_account->activeCall) return;
    CallOpParam prm;
    _account->activeCall->xfer([uri UTF8String], prm);
}

- (void)sendDtmf:(NSString *)digit {
    if (!_account || !_account->activeCall) return;
    CallSendDtmfParam dtmfParam;
    dtmfParam.method = PJSUA_DTMF_METHOD_RFC2833;
    dtmfParam.digits = [digit UTF8String];
    _account->activeCall->sendDtmf(dtmfParam);
}

- (void)hangupCall {
    if (!_account || !_account->activeCall) return;
    CallOpParam prm;
    _account->activeCall->hangup(prm);
    _account->activeCall.reset();
}

- (void)handleIpChange {
    // D-09/RESEARCH.md Pattern 3: called from NetworkChangeMonitor.swift's
    // NWPathMonitor observer only once the new network has a usable path
    // (never on old-interface teardown). restartListener + shutdownTransport
    // mirror the IpChangeParam shape documented at docs.pjsip.org's
    // ip_change.html.
    IpChangeParam param;
    param.restartListener = true;
    param.shutdownTransport = true;
    _endpoint.handleIpChange(param);
}

@end
