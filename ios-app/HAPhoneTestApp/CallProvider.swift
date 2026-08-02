import CallKit

/// Minimal CXProviderConfiguration + CXProviderDelegate for the placeholder
/// call -- Pattern 2 (Minimal CXProviderConfiguration) from 01-RESEARCH.md.
enum CallProviderFactory {
    static func makeProvider() -> CXProvider {
        let configuration = CXProviderConfiguration(localizedName: "HA-Phone Test")
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        return CXProvider(configuration: configuration)
    }
}

final class CallProviderDelegate: NSObject, CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {}

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
    }
}
