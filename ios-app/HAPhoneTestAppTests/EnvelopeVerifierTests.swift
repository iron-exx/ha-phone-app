import XCTest
@testable import HAPhoneTestApp

/// Golden fixture shared with `tools/tests/test_envelope.py` (Plan 01) --
/// canonical bytes and signature MUST match byte-for-byte across languages.
final class EnvelopeVerifierTests: XCTestCase {
    private let publicKeyHex = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"

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

    private let expectedCanonicalBytes = """
    {"call_id":"11111111-1111-1111-1111-111111111111","call_type":"audio","caller":"HA-Phone Testanruf","event_id":"22222222-2222-2222-2222-222222222222","expires_at":1700000030,"issued_at":1700000000,"v":1}
    """

    private let expectedSignatureB64 = "OkK98iMhFXjo/2IRqckexlCdJfj2dQo4T/CMoedRvwOGfTCsGrA3et4nxvSvlMActs+ijn6bW91Ge3+gcIn/BA=="

    func testGoldenCanonicalBytesMatchFixture() throws {
        let bytes = try XCTUnwrap(EnvelopeVerifier.canonicalBytes(from: fixtureDict))
        let string = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertEqual(string, expectedCanonicalBytes)
    }

    func testGoldenSignatureVerifies() {
        var dict = fixtureDict
        dict["sig"] = expectedSignatureB64
        XCTAssertTrue(EnvelopeVerifier.verify(dict: dict, publicKeyHex: publicKeyHex))
    }

    func testTamperedCallerFailsVerification() {
        var dict = fixtureDict
        dict["caller"] = "HA-Phone Testanrufx"
        dict["sig"] = expectedSignatureB64
        XCTAssertFalse(EnvelopeVerifier.verify(dict: dict, publicKeyHex: publicKeyHex))
    }

    func testIsExpiredTrueForPastTimestamp() {
        var dict = fixtureDict
        dict["expires_at"] = 1_700_000_030
        XCTAssertTrue(EnvelopeVerifier.isExpired(dict: dict, now: 1_700_000_031))
    }

    func testIsExpiredFalseForFutureTimestamp() {
        var dict = fixtureDict
        dict["expires_at"] = 1_700_000_030
        XCTAssertFalse(EnvelopeVerifier.isExpired(dict: dict, now: 1_700_000_029))
    }
}
