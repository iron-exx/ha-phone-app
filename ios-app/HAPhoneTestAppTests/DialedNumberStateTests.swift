import XCTest
@testable import HAPhoneTestApp

final class DialedNumberStateTests: XCTestCase {
    func testAppendSanitizesEachCharacter() {
        let state = DialedNumberState()
        "1a50".forEach { state.append($0) }
        XCTAssertEqual(state.current, "150")
    }

    func testBackspaceRemovesLastCharacter() {
        let state = DialedNumberState()
        "150".forEach { state.append($0) }
        state.backspace()
        XCTAssertEqual(state.current, "15")
    }

    func testClearEmptiesState() {
        let state = DialedNumberState()
        "150".forEach { state.append($0) }
        state.clear()
        XCTAssertEqual(state.current, "")
    }

    func testToCallUriBuildsTlsUri() throws {
        let state = DialedNumberState()
        "150".forEach { state.append($0) }
        XCTAssertEqual(try state.toCallUri(domain: "pbx.local:5061"), "sip:150@pbx.local:5061;transport=tls")
    }

    func testToCallUriThrowsWhenEmpty() {
        XCTAssertThrowsError(try DialedNumberState().toCallUri(domain: "pbx.local:5061"))
    }
}
