import AppKit

/// Screenshots from anywhere: ⌃⌥A captures an area and offers marks, copy, save, pin, text recognition,
/// and recording; ⌃⌥O captures an area and copies its text; ⌃⌥⇧A records an area to an MP4 file and,
/// pressed again, stops. All are system hotkeys registered when the input method starts, so they work in
/// every app and with any input source. Capturing needs Screen Recording access; recognition runs on the
/// Mac (Vision).
@MainActor
public final class ScreenshotService {
    public static let shared = ScreenshotService()

    /// The hotkeys registered now; empty when screenshots are off.
    private var registered: [TranslationHotkey]?
    private var overlay: ScreenshotOverlay?
    private var starting = false
    private var askedForPermission = false
    private var previousApp: NSRunningApplication?
    private var recording: ScreenRecordingSession?
    /// Between choosing the area and the first frame; the hotkey does nothing then.
    private var startingRecording = false

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
        let wanted = settings.isEnabled ? [settings.hotkey, settings.ocrHotkey, settings.recordHotkey] : []
        guard wanted != registered else {
            return
        }
        registered = wanted
        guard settings.isEnabled else {
            GlobalHotkeys.shared.unregister(.screenshot)
            GlobalHotkeys.shared.unregister(.screenshotOCR)
            GlobalHotkeys.shared.unregister(.screenRecording)
            log("screenshot hotkeys: off")
            return
        }
        let capture = GlobalHotkeys.shared.register(settings.hotkey, id: .screenshot) {
            ScreenshotService.shared.start(.capture)
        }
        let recognize = GlobalHotkeys.shared.register(settings.ocrHotkey, id: .screenshotOCR) {
            ScreenshotService.shared.start(.recognizeText)
        }
        let record = GlobalHotkeys.shared.register(settings.recordHotkey, id: .screenRecording) {
            ScreenshotService.shared.toggleRecording()
        }
        log("screenshot hotkeys: \(settings.hotkey.displayString) status \(capture), \(settings.ocrHotkey.displayString) status \(recognize), \(settings.recordHotkey.displayString) status \(record)")
    }

    func toggleRecording() {
        if let recording {
            recording.stop()
        } else {
            start(.record)
        }
    }

    func start(_ mode: ScreenshotOverlay.Mode) {
        guard overlay == nil, !starting, !startingRecording else {
            return
        }
        // The overlay would freeze the screen in the middle of the video.
        if recording != nil {
            ScreenshotToast.show("Stop the recording first (\(ScreenshotSettings(systemDefaults: nil).recordHotkey.displayString))")
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
                ScreenshotToast.show("Screenshots require macOS 14 or later")
            } catch {
                self.log("screenshot: capture failed \(error)")
                ScreenshotToast.show("Screenshot failed: \(error)")
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
        ScreenshotToast.show("Screenshots need the Screen Recording permission: System Settings › Privacy & Security › Screen & System Audio Recording, turn on LinguaType, then quit and reopen it when prompted", duration: 6)
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
            ScreenshotToast.show("Screenshot copied")
        case .save:
            Self.save(image: output.image, scale: output.scale)
        case .pin:
            ScreenshotPin.show(image: output.image, scale: output.scale, screenRect: output.screenRect)
        case .recognizeText:
            recognizeAndCopy(output.plainImage)
        case .record:
            startRecording(output.screenRect)
        case .cancel:
            break
        }
    }

    // MARK: Recording

    private func startRecording(_ area: CGRect) {
        let settings = ScreenshotSettings()
        let folder = settings.saveFolder
        let name = ScreenshotSettings.fileName(at: Date(), prefix: "Screen Recording", fileExtension: "mp4") { name in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
        }
        let url = folder.appendingPathComponent(name)
        startingRecording = true
        Task { @MainActor in
            defer { self.startingRecording = false }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                self.recording = try await ScreenRecordingSession.start(
                    area: area, frameRate: settings.frameRate, url: url, stopHint: settings.recordHotkey.displayString
                ) { [weak self] result in
                    self?.recordingFinished(result)
                }
                self.log("screen recording: started at \(settings.frameRate) fps")
            } catch {
                self.log("screen recording: start failed \(error)")
                ScreenshotToast.show("Recording failed: \(error.localizedDescription)", duration: 4)
            }
        }
    }

    /// Copies the file, so it can be pasted into a chat or a mail, and says where it was saved.
    private func recordingFinished(_ result: Result<ScreenRecordingSession.Outcome, Error>) {
        recording = nil
        switch result {
        case .success(let outcome):
            let size = (try? outcome.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "?"
            log("screen recording: saved \(outcome.width)×\(outcome.height), \(Int(outcome.duration)) s, \(size)\(outcome.interruption.map { ", stopped by \($0)" } ?? "")")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([outcome.url as NSURL])
            let folder = FileManager.default.displayName(atPath: outcome.url.deletingLastPathComponent().path)
            let prefix = outcome.interruption.map { "Recording stopped: \($0). " } ?? ""
            ScreenshotToast.show(
                "\(prefix)Saved to \"\(folder)\" and copied: \(outcome.url.lastPathComponent) (\(ScreenRecordingGeometry.elapsedText(outcome.duration)), \(size))",
                duration: outcome.interruption == nil ? 3 : 6
            )
        case .failure(let error):
            log("screen recording: failed \(error)")
            ScreenshotToast.show("Recording failed: \(error.localizedDescription)", duration: 4)
        }
    }

    /// Copies the text in `image`; says how many characters, or that none were found.
    func recognizeAndCopy(_ image: CGImage) {
        ScreenshotToast.show("Recognizing text…", duration: 30)
        let started = Date()
        Task { @MainActor in
            do {
                let text = try await ScreenshotOCR.recognize(image)
                self.log("screenshot: recognized \(text.count) characters in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                guard !text.isEmpty else {
                    ScreenshotToast.show("No text recognized")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                ScreenshotToast.show("Recognized text copied (\(text.count) characters)")
            } catch {
                ScreenshotToast.show("Recognition failed: \(error.localizedDescription)")
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
                ScreenshotToast.show("Save failed: could not create the image")
                return
            }
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            ScreenshotToast.show("Saved to \"\(FileManager.default.displayName(atPath: folder.path))\": \(name)", duration: 2.5)
        } catch {
            ScreenshotToast.show("Save failed: \(error.localizedDescription)", duration: 4)
        }
    }

    private func log(_ event: String) {
        AIAssistEventLog.shared.append(event, app: "-")
    }
}
