import SwiftUI
import PushKit
import CallKit

/// Wires PKPushRegistry + CXProvider + PushHandler together at launch.
///
/// The dev fixture public key below is the Plan 01 test key (matches the
/// golden fixture EnvelopeVerifier.swift is verified against) -- replace via
/// `keygen.py`'s real generated key before real-device testing.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let devFixturePublicKeyHex = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"

    private var pushRegistry: PKPushRegistry?
    private var callProvider: CXProvider?
    private var callProviderDelegate: CallProviderDelegate?
    private var pushHandler: PushHandler?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let provider = CallProviderFactory.makeProvider()
        let providerDelegate = CallProviderDelegate()
        provider.setDelegate(providerDelegate, queue: nil)

        let handler = PushHandler(
            callReporter: provider,
            callEnder: CXCallControllerEnder(),
            diagnosticsLog: FileDiagnosticsLog(),
            verifierPublicKeyHex: devFixturePublicKeyHex
        )

        let registry = PKPushRegistry(queue: .main)
        registry.delegate = handler
        registry.desiredPushTypes = [.voIP]

        self.callProvider = provider
        self.callProviderDelegate = providerDelegate
        self.pushHandler = handler
        self.pushRegistry = registry

        return true
    }
}

@main
struct HAPhoneTestAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DiagnosticsView()
        }
    }
}
