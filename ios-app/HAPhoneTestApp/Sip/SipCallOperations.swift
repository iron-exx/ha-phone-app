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
