import Foundation
import InputMethodKit

public final class IMEHostServer {
    private(set) var server: IMKServer?

    public init() {}

    @discardableResult
    public func start() -> IMKServer? {
        let bundle = Bundle.main
        let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
            ?? IMEHostConfiguration.connectionName
        let bundleIdentifier = bundle.bundleIdentifier ?? IMEHostConfiguration.bundleIdentifier

        let server = IMKServer(
            name: connectionName,
            bundleIdentifier: bundleIdentifier
        )
        self.server = server
        return server
    }
}
