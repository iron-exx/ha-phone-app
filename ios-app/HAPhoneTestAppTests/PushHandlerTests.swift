import XCTest
import CallKit
@testable import HAPhoneTestApp

private final class MockCallReporter: IncomingCallReporting {
    private(set) var callOrder: [String] = []
    private(set) var reportedUUIDs: [UUID] = []

    func reportNewIncomingCall(with uuid: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void) {
        callOrder.append("reportNewIncomingCall")
        reportedUUIDs.append(uuid)
        completion(nil)
    }
}

private final class MockCallEnder: CallEnding {
    private(set) var endedUUIDs: [UUID] = []

    func endCall(uuid: UUID) {
        endedUUIDs.append(uuid)
    }
}

private final class MockDiagnosticsLog: DiagnosticsLogging {
    private(set) var events: [(event: String, timestamp: Date)] = []

    func record(event: String, timestamp: Date) {
        events.append((event, timestamp))
    }

    func readAll() -> [String] {
        events.map { $0.event }
    }
}

final class PushHandlerTests: XCTestCase {
    private let publicKeyHex = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"
    private let validSignatureB64 = "OkK98iMhFXjo/2IRqckexlCdJfj2dQo4T/CMoedRvwOGfTCsGrA3et4nxvSvlMActs+ijn6bW91Ge3+gcIn/BA=="

    private var fixtureDict: [String: Any] {
        [
            "call_id": "11111111-1111-1111-1111-111111111111",
            "call_type": "audio",
            "caller": "HA-Phone Testanruf",
            "event_id": "22222222-2222-2222-2222-222222222222",
            "expires_at": 1_700_000_030,
            "issued_at": 1_700_000_000,
            "v": 1,
        ]
    }

    private func makeHandler(reporter: MockCallReporter, ender: MockCallEnder, log: MockDiagnosticsLog) -> PushHandler {
        PushHandler(callReporter: reporter, callEnder: ender, diagnosticsLog: log, verifierPublicKeyHex: publicKeyHex)
    }

    func testWellFormedPayloadReportsImmediately() {
        let reporter = MockCallReporter()
        let ender = MockCallEnder()
        let log = MockDiagnosticsLog()
        let handler = makeHandler(reporter: reporter, ender: ender, log: log)

        var dict = fixtureDict
        dict["sig"] = validSignatureB64

        let expectation = expectation(description: "completion called")
        handler.handleIncomingPush(dict: dict) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(reporter.callOrder.filter { $0 == "reportNewIncomingCall" }.count, 1)
        // reportNewIncomingCall must happen before any verification-related log event.
        let reportedAtIndex = log.events.firstIndex { $0.event == "reportedAt" }
        XCTAssertNotNil(reportedAtIndex)
        let verificationIndex = log.events.firstIndex { $0.event == "signatureValid" || $0.event == "signatureInvalid" }
        XCTAssertNotNil(verificationIndex)
        XCTAssertLessThan(reportedAtIndex!, verificationIndex!)
    }

    func testMalformedPayloadStillReports() {
        let reporter = MockCallReporter()
        let ender = MockCallEnder()
        let log = MockDiagnosticsLog()
        let handler = makeHandler(reporter: reporter, ender: ender, log: log)

        let expectation = expectation(description: "completion called")
        handler.handleIncomingPush(dict: [:]) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(reporter.callOrder.filter { $0 == "reportNewIncomingCall" }.count, 1)
        XCTAssertEqual(reporter.reportedUUIDs.count, 1)
    }

    func testExpiredPayloadStillReportsThenEnds() {
        let reporter = MockCallReporter()
        let ender = MockCallEnder()
        let log = MockDiagnosticsLog()
        let handler = makeHandler(reporter: reporter, ender: ender, log: log)

        var dict = fixtureDict
        dict["expires_at"] = 1_600_000_000 // far in the past
        dict["sig"] = validSignatureB64 // stale sig from a different expires_at, irrelevant to expiry check

        let expectation = expectation(description: "completion called")
        handler.handleIncomingPush(dict: dict) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(reporter.callOrder.filter { $0 == "reportNewIncomingCall" }.count, 1)
        XCTAssertEqual(ender.endedUUIDs.count, 1)
    }

    func testTamperedSignaturePayloadStillReports() {
        let reporter = MockCallReporter()
        let ender = MockCallEnder()
        let log = MockDiagnosticsLog()
        let handler = makeHandler(reporter: reporter, ender: ender, log: log)

        var dict = fixtureDict
        dict["sig"] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="

        let expectation = expectation(description: "completion called")
        handler.handleIncomingPush(dict: dict) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(reporter.callOrder.filter { $0 == "reportNewIncomingCall" }.count, 1)
        XCTAssertTrue(log.events.contains { $0.event == "signatureInvalid" })
    }

    func testPushCredentialsUpdateRecordsToken() {
        let hex = PushHandler.tokenHex(fromRawTokenData: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(hex, "deadbeef")

        let reporter = MockCallReporter()
        let ender = MockCallEnder()
        let log = MockDiagnosticsLog()
        let handler = makeHandler(reporter: reporter, ender: ender, log: log)

        handler.recordPushTokenUpdate(hex: hex)
        XCTAssertTrue(log.events.contains { $0.event.contains("pushTokenUpdated") && $0.event.contains(hex) })
    }
}
