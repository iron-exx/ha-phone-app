import SwiftUI
import CallKit

/// CALL-03: outgoing call entry screen. Reports the outgoing call to
/// CallKit via CXStartCallAction so didActivate fires for audio-session
/// setup (RESEARCH.md) -- the actual SipCallController.makeCall happens
/// inside CallProviderDelegate's CXStartCallAction handler, not here.
struct OutgoingCallView: View {
    @StateObject private var dialedNumber = DialedNumberState()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(dialedNumber.current.isEmpty ? "Enter extension" : dialedNumber.current)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(dialedNumber.current.isEmpty ? .secondary : .primary)

            DialpadView(onDigit: { dialedNumber.append($0) })

            Button("Call") {
                placeCall()
            }
            .disabled(dialedNumber.current.isEmpty)
        }
        .padding(32)
    }

    private func placeCall() {
        let uuid = UUID()
        let handle = CXHandle(type: .generic, value: dialedNumber.current)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        CXCallController().request(CXTransaction(action: startAction)) { _ in }
    }
}
