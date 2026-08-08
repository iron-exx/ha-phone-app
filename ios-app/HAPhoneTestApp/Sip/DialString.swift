import Foundation

enum DialStringError: Error { case noDigits }

/// Client-side digit sanitization mirroring the server-side `_dial_string`
/// pattern in ~/projects/Ha-Phone/ha-phone/backend/routers/extensions.py
/// (Security V5 -- T-2-08). Reused for dial (CALL-03), DTMF (CALL-02), and
/// blind-transfer target entry (CALL-04) per D-12/D-13/D-14.
enum DialString {
    private static let disallowed = try! NSRegularExpression(pattern: "[^0-9+*#]")

    static func sanitize(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        return disallowed.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
    }

    static func toSipUri(sanitized: String, domain: String) throws -> String {
        guard !sanitized.isEmpty else { throw DialStringError.noDigits }
        return "sip:\(sanitized)@\(domain);transport=tls"
    }
}
