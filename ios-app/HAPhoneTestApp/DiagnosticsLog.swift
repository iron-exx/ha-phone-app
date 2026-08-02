import Foundation

/// Persisted on-device JSON-lines log of sentAt/receivedAt/reportedAt/
/// signature-validity/pushToken events, readable after app termination
/// (D-10 consequence: no live Xcode console available for a fully-terminated
/// app test, so diagnostics must survive process death via disk persistence).
protocol DiagnosticsLogging {
    func record(event: String, timestamp: Date)
    func readAll() -> [String]
}

final class FileDiagnosticsLog: DiagnosticsLogging {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "de.systemwerk.haphone.test.diagnostics", qos: .utility)

    init(fileURL: URL = FileDiagnosticsLog.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("diagnostics.log")
    }

    func record(event: String, timestamp: Date) {
        queue.sync {
            let iso = ISO8601DateFormatter().string(from: timestamp)
            let line = "{\"event\":\"\(event)\",\"at\":\"\(iso)\"}\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }

    func readAll() -> [String] {
        queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8))?
                .split(separator: "\n")
                .map(String.init) ?? []
        }
    }
}
