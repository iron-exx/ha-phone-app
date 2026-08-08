import SwiftUI
import PushKit
import CallKit

/// Real HA-Phone test-extension credentials (Plan 01 checkpoint output),
/// read from Info.plist at runtime -- Info.plist's SIPTest* keys are
/// populated at build time via Secrets.xcconfig's $(SIP_TEST_*) build
/// settings (see project.yml), never as Swift string literals in tracked
/// source. Mirrors Plan 04's Android local.properties -> BuildConfig
/// pattern (02-05 credential-substitution deviation). Secrets.xcconfig
/// itself is gitignored -- see Secrets.xcconfig.example for the template.
enum SipTestConfiguration {
    static var host: String { Bundle.main.object(forInfoDictionaryKey: "SIPTestHost") as? String ?? "" }
    static var port: String { Bundle.main.object(forInfoDictionaryKey: "SIPTestPort") as? String ?? "" }
    static var username: String { Bundle.main.object(forInfoDictionaryKey: "SIPTestUsername") as? String ?? "" }
    static var password: String { Bundle.main.object(forInfoDictionaryKey: "SIPTestPassword") as? String ?? "" }
}

/// Wires PKPushRegistry + CXProvider + PushHandler + the real PJSUA2-backed
/// SipCallController together at launch.
///
/// The dev fixture public key below is the Plan 01 test key (matches the
/// golden fixture EnvelopeVerifier.swift is verified against) -- replace via
/// `keygen.py`'s real generated key before real-device testing.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private let devFixturePublicKeyHex = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"

    private var pushRegistry: PKPushRegistry?
    private var callProvider: CXProvider?
    private(set) var callProviderDelegate: CallProviderDelegate?
    private var pushHandler: PushHandler?

    private let pjsuaBridge = PjsuaBridge()
    private(set) var sipCallController: SipCallController?
    private var networkChangeMonitor: NetworkChangeMonitor?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Self.shared = self
        pjsuaBridge.start()

        let sipDomain = "\(SipTestConfiguration.host):\(SipTestConfiguration.port)"
        let sipOps = PjsuaBridgeSipCallOperations(
            bridge: pjsuaBridge,
            domain: sipDomain,
            username: SipTestConfiguration.username,
            password: SipTestConfiguration.password
        )
        let controller = SipCallController(sipOps: sipOps, sipDomain: sipDomain)
        self.sipCallController = controller

        // D-09: mid-call network-switch resilience (RESEARCH.md Pattern 3).
        let networkMonitor = NetworkChangeMonitor(handler: NetworkChangeHandler(notifier: pjsuaBridge))
        networkMonitor.start()
        self.networkChangeMonitor = networkMonitor

        let provider = CallProviderFactory.makeProvider()
        let providerDelegate = CallProviderDelegate(sipCallController: controller)
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
    @ObservedObject private var callSessionState = CallSessionState.shared

    var body: some Scene {
        WindowGroup {
            DiagnosticsView()
                .fullScreenCover(isPresented: $callSessionState.isCallActive) {
                    ActiveCallView()
                }
        }
    }
}
