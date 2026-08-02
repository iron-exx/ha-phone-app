import XCTest
@testable import HAPhoneTestApp

final class DiagnosticsLogTests: XCTestCase {
    private func makeTempLog() -> (FileDiagnosticsLog, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-\(UUID().uuidString).log")
        return (FileDiagnosticsLog(fileURL: url), url)
    }

    override func tearDown() {
        super.tearDown()
    }

    func testWriteAppendsEventLine() {
        let (log, url) = makeTempLog()
        defer { try? FileManager.default.removeItem(at: url) }

        log.record(event: "receivedAt", timestamp: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let contents = try? String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents?.contains("receivedAt") ?? false)
    }

    func testReadAllReturnsAllRecordedLinesInOrder() {
        let (log, url) = makeTempLog()
        defer { try? FileManager.default.removeItem(at: url) }

        log.record(event: "receivedAt", timestamp: Date(timeIntervalSince1970: 0))
        log.record(event: "reportedAt", timestamp: Date(timeIntervalSince1970: 1))
        log.record(event: "pushTokenUpdated:deadbeef", timestamp: Date(timeIntervalSince1970: 2))

        let lines = log.readAll()
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("receivedAt"))
        XCTAssertTrue(lines[1].contains("reportedAt"))
        XCTAssertTrue(lines[2].contains("pushTokenUpdated:deadbeef"))
    }

    func testRecordSurvivesAcrossInstances() {
        // Simulates process termination: a new FileDiagnosticsLog instance
        // pointed at the same file must still read prior events (D-10).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        FileDiagnosticsLog(fileURL: url).record(event: "receivedAt", timestamp: Date())
        let reopened = FileDiagnosticsLog(fileURL: url)
        XCTAssertEqual(reopened.readAll().count, 1)
    }

    func testReadAllReturnsEmptyArrayWhenFileDoesNotExist() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-test-nonexistent-\(UUID().uuidString).log")
        let log = FileDiagnosticsLog(fileURL: url)
        XCTAssertEqual(log.readAll(), [])
    }
}
