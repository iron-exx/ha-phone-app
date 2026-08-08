import SwiftUI
import AVKit
import CallKit

/// Active Call screen hosting exactly the 5 CALL-01..05 controls (D-11):
/// Mute, Hold, Audio Routing, Keypad, Transfer, End Call. Presented via
/// HAPhoneTestAppApp's .fullScreenCover bound to CallSessionState.shared
/// (blocker fix, checker iteration 3).
struct ActiveCallView: View {
    @State private var isMuted = false
    @State private var isOnHold = false
    @State private var showKeypad = false
    @State private var showTransfer = false
    @StateObject private var transferState = DialedNumberState()

    var body: some View {
        VStack(spacing: 24) {
            Text("In call").font(.system(size: 28, weight: .semibold))

            HStack(spacing: 16) {
                Button(isMuted ? "Unmute" : "Mute") { toggleMute() }
                Button(isOnHold ? "Unhold" : "Hold") { toggleHold() }
                AVRoutePickerView()
                    .frame(width: 44, height: 44)
            }

            HStack(spacing: 16) {
                Button("Keypad") { showKeypad = true }
                Button("Transfer") { showTransfer = true }
            }

            Button("End Call") { endCall() }
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .padding()
                .background(Color.red)
        }
        .padding(32)
        .sheet(isPresented: $showKeypad) {
            VStack {
                Text("Keypad")
                DialpadView(onDigit: { sendDtmf($0) })
            }.padding(24)
        }
        .sheet(isPresented: $showTransfer) {
            VStack {
                Text("Transfer to")
                Text(transferState.current.isEmpty ? "Enter extension" : transferState.current).font(.system(size: 28, weight: .semibold))
                DialpadView(onDigit: { transferState.append($0) })
                Button("Transfer") {
                    try? AppDelegate.shared?.sipCallController?.transfer(transferState.current)
                    showTransfer = false
                }
            }.padding(24)
        }
    }

    // Mute/Hold route through CXCallController so CallKit's own system UI
    // (and its isMuted/isOnHold state) stays in sync -- the actual
    // sipCallController.mute()/hold() calls happen inside
    // CallProviderDelegate's CXSetMutedCallAction/CXSetHeldCallAction
    // handlers (Plan 05/07), not directly from this view.
    private func toggleMute() {
        guard let uuid = AppDelegate.shared?.callProviderDelegate?.activeCallUUID else { return }
        isMuted.toggle()
        let action = CXSetMutedCallAction(call: uuid, muted: isMuted)
        CXCallController().request(CXTransaction(action: action)) { _ in }
    }

    private func toggleHold() {
        guard let uuid = AppDelegate.shared?.callProviderDelegate?.activeCallUUID else { return }
        isOnHold.toggle()
        let action = CXSetHeldCallAction(call: uuid, onHold: isOnHold)
        CXCallController().request(CXTransaction(action: action)) { _ in }
    }

    private func sendDtmf(_ digit: Character) {
        guard let uuid = AppDelegate.shared?.callProviderDelegate?.activeCallUUID else { return }
        let action = CXPlayDTMFCallAction(call: uuid, digits: String(digit), type: .singleTone)
        CXCallController().request(CXTransaction(action: action)) { _ in }
    }

    private func endCall() {
        guard let uuid = AppDelegate.shared?.callProviderDelegate?.activeCallUUID else { return }
        let action = CXEndCallAction(call: uuid)
        CXCallController().request(CXTransaction(action: action)) { _ in }
    }
}
