import Cocoa
import IMEHostCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hostServer = IMEHostServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = hostServer.start()
    }
}
