import Foundation
import PushKit
import CallKit

protocol IncomingCallReporting {
    func reportNewIncomingCall(with uuid: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void)
}
extension CXProvider: IncomingCallReporting {}

protocol CallEnding {
    func endCall(uuid: UUID)
}
struct CXCallControllerEnder: CallEnding {
    let controller = CXCallController()
    func endCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        controller.request(CXTransaction(action: action)) { _ in }
    }
}

/// PKPushRegistryDelegate that unconditionally reports every VoIP push to
/// CallKit before any async verification work (Pitfall 1: not reporting
/// every VoIP push to CallKit synchronously is the platform-level hazard --
/// Apple disables the app's VoIP entitlement for repeat offenders).
final class PushHandler: NSObject, PKPushRegistryDelegate {
    private let callReporter: IncomingCallReporting
    private let callEnder: CallEnding
    private let diagnosticsLog: DiagnosticsLogging
    private let verifierPublicKeyHex: String

    init(callReporter: IncomingCallReporting, callEnder: CallEnding, diagnosticsLog: DiagnosticsLogging, verifierPublicKeyHex: String) {
        self.callReporter = callReporter
        self.callEnder = callEnder
        self.diagnosticsLog = diagnosticsLog
        self.verifierPublicKeyHex = verifierPublicKeyHex
    }

    // MARK: - Token registration (needed so the developer can copy the token
    // into `tools/push_trigger.py --device-token` for manual testing -- Plan 06).

    static func tokenHex(fromRawTokenData data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        recordPushTokenUpdate(hex: Self.tokenHex(fromRawTokenData: pushCredentials.token))
    }

    /// Thin wrapper both the real delegate method above and tests call --
    /// `PKPushCredentials` has no public initializer, so tests exercise this
    /// entry point directly with a precomputed hex string instead.
    func recordPushTokenUpdate(hex: String) {
        diagnosticsLog.record(event: "pushTokenUpdated:\(hex)", timestamp: Date())
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        diagnosticsLog.record(event: "pushTokenInvalidated", timestamp: Date())
    }

    // MARK: - Incoming push (Pitfall 1: report first, unconditionally, always)

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        // PKPushPayload.dictionaryPayload is [AnyHashable: Any] (matches the
        // Obj-C NSDictionary bridging); handleIncomingPush's [String: Any]
        // entry point below is what tests construct directly, so narrow the
        // keys here rather than loosening the testable signature.
        let stringKeyedPayload = payload.dictionaryPayload.reduce(into: [String: Any]()) { result, entry in
            if let key = entry.key as? String {
                result[key] = entry.value
            }
        }
        handleIncomingPush(dict: stringKeyedPayload, completion: completion)
    }

    /// Core payload-handling logic, extracted into a plain-`[String: Any]`
    /// entry point so it is directly testable: `PKPushPayload` has no public
    /// initializer and cannot be constructed with custom dictionaries in unit
    /// tests, the same constraint the plan already calls out for
    /// `PKPushCredentials` in `tokenHex(fromRawTokenData:)` above.
    func handleIncomingPush(dict: [String: Any], completion: @escaping () -> Void) {
        diagnosticsLog.record(event: "receivedAt", timestamp: Date())

        let callIdString = dict["call_id"] as? String ?? UUID().uuidString
        let uuid = UUID(uuidString: callIdString) ?? UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "HA-Phone Testanruf")
        update.localizedCallerName = "HA-Phone Testanruf"
        update.hasVideo = false

        // MANDATORY: report first, synchronously, unconditionally -- Pitfall 1.
        callReporter.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
            guard let self else { completion(); return }
            self.diagnosticsLog.record(event: "reportedAt", timestamp: Date())

            let isValid = EnvelopeVerifier.verify(dict: dict, publicKeyHex: self.verifierPublicKeyHex)
            let isExpired = EnvelopeVerifier.isExpired(dict: dict)
            self.diagnosticsLog.record(event: isValid ? "signatureValid" : "signatureInvalid", timestamp: Date())

            if isExpired || !isValid {
                self.callEnder.endCall(uuid: uuid)
            }
            completion()
        }
    }
}
