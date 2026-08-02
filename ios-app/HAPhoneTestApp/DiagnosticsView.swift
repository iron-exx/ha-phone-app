import SwiftUI
import UIKit

/// D-10 fallback: this view is how the developer inspects diagnostics on a
/// device that has no live Xcode console attached (e.g. after the app was
/// fully terminated and woken by a VoIP push) -- it surfaces the current
/// VoIP push token for manual copy-paste into `tools/push_trigger.py
/// --device-token`, and exports the full log via the share sheet.
struct DiagnosticsView: View {
    @State private var logLines: [String] = []

    private var currentToken: String? {
        logLines
            .reversed()
            .compactMap { line -> String? in
                guard let range = line.range(of: "pushTokenUpdated:") else { return nil }
                let afterPrefix = line[range.upperBound...]
                let token = afterPrefix.prefix { $0 != "\"" }
                return String(token)
            }
            .first
    }

    var body: some View {
        NavigationView {
            List {
                Section("Current VoIP Token") {
                    if let token = currentToken {
                        Text(token)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy Token") {
                            UIPasteboard.general.string = token
                        }
                    } else {
                        Text("No token registered yet")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Log") {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: FileDiagnosticsLog.defaultURL()) {
                        Label("Share Log", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
        }
    }

    private func reload() {
        logLines = FileDiagnosticsLog().readAll()
    }
}

/// UIActivityViewController wrapper -- D-10 fallback for exporting the
/// diagnostics log file without a live Xcode console, kept as an explicit
/// UIViewControllerRepresentable in case a call site needs the classic
/// share-sheet presentation instead of SwiftUI's `ShareLink`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
