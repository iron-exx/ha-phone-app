import CallKit
import AVFoundation

enum CallProviderFactory {
    static func makeProvider() -> CXProvider {
        let configuration = CXProviderConfiguration(localizedName: "HA-Phone Test")
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        return CXProvider(configuration: configuration)
    }
}

final class CallProviderDelegate: NSObject, CXProviderDelegate {
    private let sipCallController: SipCallController

    init(sipCallController: SipCallController) {
        self.sipCallController = sipCallController
    }

    func providerDidReset(_ provider: CXProvider) {}

    // Re-confirmed correct during the Blocker-1/2 revision pass (checker
    // iteration 4): this fires only on CallKit's genuine user-answer
    // signal -- CallKit invokes `perform action: CXAnswerCallAction`
    // exclusively when the user actually answers (system UI, CarPlay,
    // Bluetooth answer button, etc.), never at call-reporting/
    // registration time. Unlike Android's CallRegistration.kt (which had
    // the equivalent bug -- Blocker 2 -- and required a fix in Plan 04),
    // this handler was already correct: the real SIP answer only ever
    // fires from here, never from PushHandler.swift's report-the-call
    // step.
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let succeeded = sipCallController.answer()
        action.fulfill()
        if !succeeded {
            // CR-01 precedent: end the call rather than let it ring forever.
            let endAction = CXEndCallAction(call: action.callUUID)
            CXCallController().request(CXTransaction(action: endAction)) { _ in }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        sipCallController.hangup()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        sipCallController.hold(action.isOnHold)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        sipCallController.mute(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        sipCallController.sendDtmf(action.digits)
        action.fulfill()
    }

    // CALL-03: outgoing calls must be reported to CallKit via
    // CXStartCallAction (Plan 05 only wired incoming-call actions).
    // reportOutgoingCall(startedConnectingAt:) followed by makeCall then
    // reportOutgoingCall(connectedAt:) is what triggers didActivate for
    // outgoing calls -- the same audio-session activation path incoming
    // calls already get.
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        do {
            try sipCallController.makeCall(action.handle.value)
            action.fulfill()
            provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
        } catch {
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        AudioSessionCoordinator.activate(audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        AudioSessionCoordinator.deactivate(audioSession)
    }
}

// CXTransferCallAction for blind transfer (CALL-04) is triggered from
// OutgoingCallView/ActiveCallView's UI in Plan 07 via
// CXCallController().request(...) directly -- no separate delegate handler
// needed here since SipCallController.transfer(_:) is called directly from
// the UI layer, matching D-14's dialpad-reuse decision. Blind transfer does
// not require a CallKit action handler the way hold/DTMF do, since it
// doesn't change CallKit's own held/muted state.
