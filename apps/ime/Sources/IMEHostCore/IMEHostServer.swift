import Foundation
import InputMethodKit

public final class IMEHostServer {
    private(set) var server: IMKServer?

    public init() {}

    @discardableResult
    public func start() -> IMKServer {
        let server = IMKServer(
            name: IMEHostConfiguration.connectionName,
            bundleIdentifier: IMEHostConfiguration.bundleIdentifier
        )
        self.server = server
        return server
    }
}
