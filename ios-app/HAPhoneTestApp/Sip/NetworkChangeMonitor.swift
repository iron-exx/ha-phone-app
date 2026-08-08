import Network

/// Real implementor: PjsuaBridge (its Obj-C `handleIpChange` selector
/// already matches this protocol's requirement, so `PjsuaBridge` conforms
/// with zero extra code via the extension below).
protocol IpChangeNotifying {
    func handleIpChange()
}

extension PjsuaBridge: IpChangeNotifying {}

/// Pure decision logic invoked by the real NWPathMonitor callback --
/// kept separate from NWPathMonitor itself so this seam is unit-testable
/// without a real network stack (D-09).
final class NetworkChangeHandler {
    private let notifier: IpChangeNotifying
    init(notifier: IpChangeNotifying) { self.notifier = notifier }

    /// Called only once the new network path is satisfied (usable),
    /// never on old-interface teardown.
    func onPathSatisfied() {
        notifier.handleIpChange()
    }
}

/// Real NWPathMonitor wiring -- constructed once from
/// HAPhoneTestAppApp.swift's AppDelegate, started alongside PjsuaBridge.
final class NetworkChangeMonitor {
    private let monitor = NWPathMonitor()
    private let handler: NetworkChangeHandler
    private let queue = DispatchQueue(label: "de.haphone.app.test.network-change")

    init(handler: NetworkChangeHandler) {
        self.handler = handler
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.handler.onPathSatisfied()
        }
        monitor.start(queue: queue)
    }
}
