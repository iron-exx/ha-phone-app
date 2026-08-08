import XCTest
@testable import HAPhoneTestApp

final class DialStringTests: XCTestCase {
    func testSanitizeStripsEverythingExceptDigitsPlusStarHash() {
        XCTAssertEqual(DialString.sanitize("1a2!b3*#"), "123*#")
    }

    func testSanitizeOfEmptyStringIsEmpty() {
        XCTAssertEqual(DialString.sanitize(""), "")
    }

    func testToSipUriBuildsTlsTransportUri() throws {
        XCTAssertEqual(try DialString.toSipUri(sanitized: "50", domain: "pbx.local:5061"), "sip:50@pbx.local:5061;transport=tls")
    }

    func testToSipUriThrowsOnEmptySanitizedInput() {
        XCTAssertThrowsError(try DialString.toSipUri(sanitized: "", domain: "pbx.local:5061"))
    }
}
