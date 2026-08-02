import Foundation
import CryptoKit

/// Ed25519 envelope verification matching `tools/envelope.py` byte-for-byte.
///
/// Canonicalization contract (must stay identical to the Python reference):
///   - Only the fields in `canonicalFieldOrder` are ever serialized (the
///     `sig` field, if present, is always excluded).
///   - Keys are emitted in that fixed alphabetical order, no whitespace.
///   - Encoded as UTF-8 bytes before signing/verifying.
enum EnvelopeVerifier {
    static let canonicalFieldOrder = ["call_id", "call_type", "caller", "event_id", "expires_at", "issued_at", "v"]

    static func canonicalBytes(from dict: [String: Any]) -> Data? {
        var parts: [String] = []
        for key in canonicalFieldOrder {
            guard let value = dict[key] else { return nil }
            if let intVal = value as? Int {
                parts.append("\"\(key)\":\(intVal)")
            } else if let strVal = value as? String {
                let escaped = strVal
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                parts.append("\"\(key)\":\"\(escaped)\"")
            } else {
                return nil
            }
        }
        return ("{" + parts.joined(separator: ",") + "}").data(using: .utf8)
    }

    static func verify(dict: [String: Any], publicKeyHex: String) -> Bool {
        guard let sigB64 = dict["sig"] as? String,
              let sigData = Data(base64Encoded: sigB64),
              let canonical = canonicalBytes(from: dict),
              let pubKeyData = Data(hexEncoded: publicKeyHex),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
        else { return false }
        return publicKey.isValidSignature(sigData, for: canonical)
    }

    static func isExpired(dict: [String: Any], now: Int = Int(Date().timeIntervalSince1970)) -> Bool {
        guard let expiresAt = dict["expires_at"] as? Int else { return true }
        return now > expiresAt
    }
}

extension Data {
    init?(hexEncoded hex: String) {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
