import Foundation

/// Public SIP call-control API for iOS (CALL-01..05), mirroring Android's
/// SipCallController.kt. Always sanitizes digit input via DialString
/// before constructing a sip: URI (Security V5, T-2-08).
final class SipCallController {
    private let sipOps: SipCallOperations
    private let sipDomain: String

    init(sipOps: SipCallOperations, sipDomain: String) {
        self.sipOps = sipOps
        self.sipDomain = sipDomain
    }

    func makeCall(_ rawDigits: String) throws {
        let uri = try DialString.toSipUri(sanitized: DialString.sanitize(rawDigits), domain: sipDomain)
        sipOps.register()
        sipOps.makeCall(uri: uri)
    }

    /// Report-First pattern: called from CXProviderDelegate's
    /// CXAnswerCallAction handler, AFTER CallKit has already reported the
    /// call. Returns false on SIP negotiation failure so the caller can
    /// end the call via CXEndCallAction (CR-01 precedent).
    @discardableResult
    func answer() -> Bool {
        sipOps.register()
        return sipOps.answer()
    }

    func hold(_ onHold: Bool) {
        sipOps.hold(onHold)
    }

    func mute(_ muted: Bool) {
        sipOps.mute(muted)
    }

    func transfer(_ rawDigits: String) throws {
        let uri = try DialString.toSipUri(sanitized: DialString.sanitize(rawDigits), domain: sipDomain)
        sipOps.transfer(uri: uri)
    }

    func sendDtmf(_ rawDigit: String) {
        let digit = DialString.sanitize(rawDigit)
        guard !digit.isEmpty else { return }
        sipOps.sendDtmf(digit)
    }

    func hangup() {
        sipOps.hangup()
        sipOps.unregister()
    }
}
