import Foundation

/// Thin seam wrapping the PJSUA2 Call/Account C++ objects exposed via
/// PjsuaBridge, mirroring PushHandler.swift's protocol-abstraction pattern
/// so SipCallControllerTests can inject a mock without a real PJSUA2
/// runtime (02-PATTERNS.md).
protocol SipCallOperations {
    func register()
    func unregister()
    func makeCall(uri: String)
    func answer() -> Bool // false = SIP negotiation failed
    func hold(_ onHold: Bool)
    func mute(_ muted: Bool)
    func transfer(uri: String)
    func sendDtmf(_ digit: String)
    func hangup()
}

/// Forwards each SipCallOperations method to the corresponding real
/// PjsuaBridge Obj-C method -- the only place Swift-facing code touches
/// PjsuaBridge, keeping SipCallController itself free of any direct
/// dependency on the Obj-C++ bridge type (testable via the protocol alone).
struct PjsuaBridgeSipCallOperations: SipCallOperations {
    private let bridge: PjsuaBridge
    private let domain: String
    private let username: String
    private let password: String

    init(bridge: PjsuaBridge, domain: String, username: String, password: String) {
        self.bridge = bridge
        self.domain = domain
        self.username = username
        self.password = password
    }

    func register() {
        bridge.registerAccount(domain: domain, username: username, password: password)
    }

    func unregister() {
        bridge.unregisterAccount()
    }

    func makeCall(uri: String) {
        bridge.makeCall(uri: uri)
    }

    func answer() -> Bool {
        bridge.answerCall()
    }

    func hold(_ onHold: Bool) {
        bridge.setHold(onHold)
    }

    func mute(_ muted: Bool) {
        bridge.setMuted(muted)
    }

    func transfer(uri: String) {
        bridge.transfer(uri: uri)
    }

    func sendDtmf(_ digit: String) {
        bridge.sendDtmf(digit)
    }

    func hangup() {
        bridge.hangupCall()
    }
}
