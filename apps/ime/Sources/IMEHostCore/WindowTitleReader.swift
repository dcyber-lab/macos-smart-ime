import AppKit
import ApplicationServices

/// Reads the title of the focused window of the app being typed in, through the Accessibility API.
/// Needs the user to grant SmartIMEHost Accessibility access. Only the window title is read, never
/// window contents: Chromium and Electron apps switch on full accessibility support (and use more CPU
/// and memory) when assistive clients read their content.
enum WindowTitleReader {
    /// How long one Accessibility call may wait for an unresponsive app.
    static let timeout: Float = 0.25

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that adds SmartIMEHost to Privacy & Security › Accessibility, and opens
    /// that pane so the user can switch it on.
    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt; the global itself is not concurrency-safe in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The focused window's title in the app with this bundle identifier, or nil when it has none, the
    /// app does not answer within `timeout`, or access is not granted.
    static func focusedWindowTitle(bundleIdentifier: String) -> String? {
        guard isTrusted, let pid = processIdentifier(of: bundleIdentifier) else {
            return nil
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = window as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success else {
            return nil
        }
        return title as? String
    }

    /// The frontmost app when it matches (the usual case while typing), else any running instance.
    private static func processIdentifier(of bundleIdentifier: String) -> pid_t? {
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleIdentifier {
            return front.processIdentifier
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.processIdentifier
    }
}
