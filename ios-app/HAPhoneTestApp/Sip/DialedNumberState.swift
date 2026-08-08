import Foundation
import Combine

/// Accumulates dialed digits for the 3 reuse contexts (D-12/D-13/D-14):
/// outgoing-call dialing, in-call DTMF entry, blind-transfer target entry.
/// Mirrors Android's DialedNumberState.kt exactly.
final class DialedNumberState: ObservableObject {
    @Published private(set) var current: String = ""

    func append(_ char: Character) {
        let sanitized = DialString.sanitize(String(char))
        if !sanitized.isEmpty { current += sanitized }
    }

    func backspace() {
        if !current.isEmpty { current.removeLast() }
    }

    func clear() {
        current = ""
    }

    func toCallUri(domain: String) throws -> String {
        try DialString.toSipUri(sanitized: current, domain: domain)
    }
}
