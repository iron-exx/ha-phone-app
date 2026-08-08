import XCTest
@testable import HAPhoneTestApp

private final class MockIpChangeNotifier: IpChangeNotifying {
    private(set) var callCount = 0
    func handleIpChange() { callCount += 1 }
}

final class NetworkChangeHandlerTests: XCTestCase {
    func testOnPathSatisfiedInvokesHandleIpChangeOnNotifier() {
        let mock = MockIpChangeNotifier()
        let handler = NetworkChangeHandler(notifier: mock)
        handler.onPathSatisfied()
        XCTAssertEqual(mock.callCount, 1)
    }
}
