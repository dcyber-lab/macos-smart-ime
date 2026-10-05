import Cocoa
import IMEHostCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hostServer = IMEHostServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard hostServer.start() != nil else {
            NSLog("SmartIMEHost: IMKServer failed to start; exiting so the system can relaunch.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        GlobalSelectionAssist.shared.install()
        ScreenshotService.shared.install()
        ClipboardService.shared.install()
    }
}
