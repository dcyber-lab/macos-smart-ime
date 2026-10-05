import AppKit
import ScreenCaptureKit

enum ScreenshotCaptureError: Error {
    case permissionDenied
    case requiresNewerSystem
    case failed(String)
}

/// One display, frozen when the hotkey was pressed, and the windows on it (front to back) for picking
/// a window with a click.
struct ScreenSnapshot {
    let screenFrame: CGRect
    let canvas: ScreenshotCanvas
    let windowFrames: [CGRect]
}

/// Captures every display with ScreenCaptureKit (needs Screen Recording access).
enum ScreenshotCapture {
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time; afterwards macOS only lists the app in System Settings.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func captureScreens() async throws -> [ScreenSnapshot] {
        guard #available(macOS 14.0, *) else {
            throw ScreenshotCaptureError.requiresNewerSystem
        }
        guard hasPermission else {
            throw ScreenshotCaptureError.permissionDenied
        }
        // Window bounds come first, before any overlay shows; they need no permission.
        let windowBounds = visibleWindowBounds()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenshotCaptureError.failed(error.localizedDescription)
        }
        var snapshots: [ScreenSnapshot] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                continue
            }
            let scale = screen.backingScaleFactor
            let configuration = SCStreamConfiguration()
            configuration.width = Int(screen.frame.width * scale)
            configuration.height = Int(screen.frame.height * scale)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image: CGImage
            do {
                image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } catch {
                throw ScreenshotCaptureError.failed(error.localizedDescription)
            }
            let frames = windowBounds.map {
                ScreenshotGeometry.viewRect(ofWindowBounds: $0, primaryHeight: primaryHeight, screenOrigin: screen.frame.origin)
            }
            snapshots.append(ScreenSnapshot(
                screenFrame: screen.frame,
                canvas: ScreenshotCanvas(image: image, size: screen.frame.size),
                windowFrames: frames
            ))
        }
        guard !snapshots.isEmpty else {
            throw ScreenshotCaptureError.failed("没有找到显示器")
        }
        return snapshots
    }

    /// Normal app windows on screen, front to back, in global coordinates with the origin at the top left.
    private static func visibleWindowBounds() -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary),
                  bounds.width >= 40, bounds.height >= 40 else {
                return nil
            }
            return bounds
        }
    }
}
