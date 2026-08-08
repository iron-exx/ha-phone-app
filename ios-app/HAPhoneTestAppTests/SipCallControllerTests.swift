import XCTest
@testable import HAPhoneTestApp

private final class MockSipCallOperations: SipCallOperations {
    private(set) var invocations: [String] = []
    var answerSucceeds = true

    func register() { invocations.append("register") }
    func unregister() { invocations.append("unregister") }
    func makeCall(uri: String) { invocations.append("makeCall:\(uri)") }
    func answer() -> Bool { invocations.append("answer"); return answerSucceeds }
    func hold(_ onHold: Bool) { invocations.append("hold:\(onHold)") }
    func mute(_ muted: Bool) { invocations.append("mute:\(muted)") }
    func transfer(uri: String) { invocations.append("transfer:\(uri)") }
    func sendDtmf(_ digit: String) { invocations.append("sendDtmf:\(digit)") }
    func hangup() { invocations.append("hangup") }
}

final class SipCallControllerTests: XCTestCase {
    func testMakeCallSanitizesAndBuildsTlsUri() throws {
        let mock = MockSipCallOperations()
        let controller = SipCallController(sipOps: mock, sipDomain: "pbx.local:5061")
        try controller.makeCall("1a50")
        XCTAssertEqual(mock.invocations, ["register", "makeCall:sip:150@pbx.local:5061;transport=tls"])
    }

    func testSendDtmfSanitizesBeforeInvoking() {
        let mock = MockSipCallOperations()
        let controller = SipCallController(sipOps: mock, sipDomain: "pbx.local:5061")
        controller.sendDtmf("5x")
        XCTAssertEqual(mock.invocations, ["sendDtmf:5"])
    }

    func testTransferSanitizesAndBuildsTlsUri() throws {
        let mock = MockSipCallOperations()
        let controller = SipCallController(sipOps: mock, sipDomain: "pbx.local:5061")
        try controller.transfer("6!0")
        XCTAssertEqual(mock.invocations, ["transfer:sip:60@pbx.local:5061;transport=tls"])
    }

    func testHoldTogglesViaSipOps() {
        let mock = MockSipCallOperations()
        let controller = SipCallController(sipOps: mock, sipDomain: "pbx.local:5061")
        controller.hold(true)
        controller.hold(false)
        XCTAssertEqual(mock.invocations, ["hold:true", "hold:false"])
    }

    func testMuteTogglesViaSipOps() {
        let mock = MockSipCallOperations()
        let controller = SipCallController(sipOps: mock, sipDomain: "pbx.local:5061")
        controller.mute(true)
        controller.mute(false)
        XCTAssertEqual(mock.invocations, ["mute:true", "mute:false"])
    }

    func testAnswerRegistersFirstThenAnswers() {
        let mock = MockSipCallOperations()
        let controller = SipCallController(sipOps: mock, sipDomain: "pbx.local:5061")
        let succeeded = controller.answer()
        XCTAssertTrue(succeeded)
        XCTAssertEqual(mock.invocations, ["register", "answer"])
    }

    func testHangupCallsSipOpsThenUnregisters() {
        let mock = MockSipCallOperations()
        let controller = SipCallController(sipOps: mock, sipDomain: "pbx.local:5061")
        controller.hangup()
        XCTAssertEqual(mock.invocations, ["hangup", "unregister"])
    }
}
