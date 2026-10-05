import AppKit

/// Screenshots from anywhere: ⌃⌥A captures an area and offers marks, copy, save, pin, and text
/// recognition; ⌃⌥O captures an area and copies its text. Both are system hotkeys registered when the
/// input method starts, so they work in every app and with any input source. Capturing needs Screen
/// Recording access; recognition runs on the Mac (Vision).
@MainActor
public final class ScreenshotService {
    public static let shared = ScreenshotService()

    /// The hotkeys registered now; empty when screenshots are off.
    private var registered: [TranslationHotkey]?
    private var overlay: ScreenshotOverlay?
    private var starting = false
    private var askedForPermission = false
    private var previousApp: NSRunningApplication?

    private init() {}

    public func install() {
        refreshHotkeys()
        // The service lives as long as the process, so the observer is never removed.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ScreenshotService.shared.refreshHotkeys() }
        }
    }

    func refreshHotkeys() {
        // Runs on every defaults change in the process, so the system screenshot domain is not read.
        let settings = ScreenshotSettings(systemDefaults: nil)
        let wanted = settings.isEnabled ? [settings.hotkey, settings.ocrHotkey] : []
        guard wanted != registered else {
            return
        }
        registered = wanted
        guard settings.isEnabled else {
            GlobalHotkeys.shared.unregister(.screenshot)
            GlobalHotkeys.shared.unregister(.screenshotOCR)
            log("screenshot hotkeys: off")
            return
        }
        let capture = GlobalHotkeys.shared.register(settings.hotkey, id: .screenshot) {
            ScreenshotService.shared.start(.capture)
        }
        let recognize = GlobalHotkeys.shared.register(settings.ocrHotkey, id: .screenshotOCR) {
            ScreenshotService.shared.start(.recognizeText)
        }
        log("screenshot hotkeys: \(settings.hotkey.displayString) status \(capture), \(settings.ocrHotkey.displayString) status \(recognize)")
    }

    func start(_ mode: ScreenshotOverlay.Mode) {
        guard overlay == nil, !starting else {
            return
        }
        guard ScreenshotCapture.hasPermission else {
            askForPermission()
            return
        }
        starting = true
        previousApp = NSWorkspace.shared.frontmostApplication
        Task { @MainActor in
            defer { self.starting = false }
            do {
                let snapshots = try await ScreenshotCapture.captureScreens()
                let overlay = ScreenshotOverlay(snapshots: snapshots, mode: mode) { [weak self] action, output in
                    self?.finish(action, output)
                }
                self.overlay = overlay
                overlay.show()
            } catch ScreenshotCaptureError.permissionDenied {
                self.askForPermission()
            } catch ScreenshotCaptureError.requiresNewerSystem {
                ScreenshotToast.show("截图需要 macOS 14 或更新的系统")
            } catch {
                self.log("screenshot: capture failed \(error)")
                ScreenshotToast.show("截图失败：\(error)")
            }
        }
    }

    private func askForPermission() {
        // The first request shows the system prompt; later ones only list the app in System Settings.
        if !askedForPermission {
            askedForPermission = true
            if ScreenshotCapture.requestPermission() {
                return
            }
        } else {
            ScreenshotCapture.openPermissionSettings()
        }
        ScreenshotToast.show("截图需要「屏幕录制」权限：系统设置 › 隐私与安全性 › 屏幕与系统录音，打开「灵译输入法」，然后按提示退出并重新打开", duration: 6)
    }

    private func finish(_ action: ScreenshotOverlay.Action, _ output: ScreenshotOverlay.Output?) {
        overlay?.close()
        overlay = nil
        previousApp?.activate()
        previousApp = nil
        guard let output else {
            return
        }
        switch action {
        case .copy:
            Self.copy(image: output.image, scale: output.scale)
            ScreenshotToast.show("已复制截图")
        case .save:
            Self.save(image: output.image, scale: output.scale)
        case .pin:
            ScreenshotPin.show(image: output.image, scale: output.scale, screenRect: output.screenRect)
        case .recognizeText:
            recognizeAndCopy(output.plainImage)
        case .cancel:
            break
        }
    }

    /// Copies the text in `image`; says how many characters, or that none were found.
    func recognizeAndCopy(_ image: CGImage) {
        ScreenshotToast.show("正在识别文字…", duration: 30)
        let started = Date()
        Task { @MainActor in
            do {
                let text = try await ScreenshotOCR.recognize(image)
                self.log("screenshot: recognized \(text.count) characters in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                guard !text.isEmpty else {
                    ScreenshotToast.show("没有识别到文字")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                ScreenshotToast.show("已复制识别的文字（\(text.count) 字）")
            } catch {
                ScreenshotToast.show("识别失败：\(error.localizedDescription)")
            }
        }
    }

    /// PNG and TIFF, both at the capture's size in points, so pasting keeps the on-screen size.
    static func copy(image: CGImage, scale: CGFloat) {
        let item = NSPasteboardItem()
        if let png = ScreenshotRenderer.pngData(image, scale: scale) {
            item.setData(png, forType: .png)
        }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        if let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    static func save(image: CGImage, scale: CGFloat) {
        let folder = ScreenshotSettings().saveFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = ScreenshotSettings.fileName(at: Date()) { name in
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
            }
            guard let data = ScreenshotRenderer.pngData(image, scale: scale) else {
                ScreenshotToast.show("保存失败：无法生成图片")
                return
            }
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            ScreenshotToast.show("已保存到「\(FileManager.default.displayName(atPath: folder.path))」：\(name)", duration: 2.5)
        } catch {
            ScreenshotToast.show("保存失败：\(error.localizedDescription)", duration: 4)
        }
    }

    private func log(_ event: String) {
        AIAssistEventLog.shared.append(event, app: "-")
    }
}
