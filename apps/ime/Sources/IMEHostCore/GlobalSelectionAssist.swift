import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// ⌃⌥R where no text field has focus (a web page, a PDF, a read-only view): the input method gets no
/// key events there, so a global key monitor starts the same popup for the selected text. The text is
/// read by copying (⌘C) and putting the clipboard back; the result can be copied, never pasted into
/// the page. Needs Accessibility access, like the window title.
@MainActor
public final class GlobalSelectionAssist {
    public static let shared = GlobalSelectionAssist()

    /// Set when the input method itself handled the hotkey, so the global monitor stays out of it.
    nonisolated(unsafe) static var lastHandledByInputMethod = Date.distantPast

    private var monitor: Any?
    private var anchor = CGRect.zero
    private var previousApp: NSRunningApplication?
    private lazy var controller = AIRewriteController(rewriter: { AIAssistSettings().rewriter() }) { [weak self] state in
        guard let self else {
            return
        }
        TranslationPopup.shared.show(state, caretRect: self.anchor, readOnly: true)
        if state == .idle {
            self.previousApp?.activate()
            self.previousApp = nil
        }
    }

    private init() {}

    private var installedWhileTrusted = false

    /// Installs the key monitor. macOS delivers no keys to a monitor made before Accessibility access is
    /// granted, and a rebuilt (ad hoc signed) app loses the grant, so this asks once and keeps checking.
    public func install() {
        log("global hotkey: start, trusted=\(WindowTitleReader.isTrusted)")
        if !WindowTitleReader.isTrusted {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        installMonitor()
        Task { @MainActor in
            while !self.installedWhileTrusted {
                try? await Task.sleep(for: .seconds(3))
                if WindowTitleReader.isTrusted {
                    self.installMonitor()
                    self.log("global hotkey: access granted, monitor installed")
                }
            }
        }
    }

    private func log(_ event: String) {
        AIAssistEventLog.shared.append(event, app: "-")
    }

    private func installMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        installedWhileTrusted = WindowTitleReader.isTrusted
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor in
                GlobalSelectionAssist.shared.handle(keyCode: keyCode, flags: flags)
            }
        }
        TranslationPopup.shared.keyHandler = { [weak self] keyCode in
            self?.handlePopupKey(keyCode)
        }
    }

    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard AIAssistSettings().hotkey.matches(keyCode: keyCode, modifierFlags: flags), !IsSecureEventInputEnabled() else {
            return
        }
        log("global hotkey: seen")
        // The input method sees the key first when a text field has focus; give it a moment to say so.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard Date().timeIntervalSince(Self.lastHandledByInputMethod) > 0.5 else {
                self.log("global hotkey: left to the input method")
                return
            }
            await self.start()
        }
    }

    /// Also used by the input method when the focused page reports no text of its own.
    func startReadOnly() {
        log("global hotkey: handed over by the input method")
        Task { @MainActor in
            await self.start()
        }
    }

    private func start() async {
        let mouse = NSEvent.mouseLocation
        anchor = CGRect(x: mouse.x, y: mouse.y - 6, width: 1, height: 6)
        previousApp = NSWorkspace.shared.frontmostApplication
        let text = await SelectionCopier.copySelection()
        log("global hotkey: copied \(text?.count ?? 0) characters")
        controller.start(text: text, range: NSRange(location: NSNotFound, length: 0), readOnly: true)
    }

    private func handlePopupKey(_ keyCode: UInt16) {
        if case .copy(let text)? = controller.isActive ? controller.handleKey(keyCode) : nil {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

/// Reads the selection of the frontmost app by sending ⌘C and restoring the clipboard afterwards. Reading
/// through the Accessibility API would switch on full accessibility support in Chromium and Electron apps.
enum SelectionCopier {
    static func copySelection() async -> String? {
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let before = board.changeCount
        // Let the modifiers of the hotkey come up before the copy is sent.
        try? await Task.sleep(for: .milliseconds(120))
        send(keyCode: 8, flags: .maskCommand)
        var text: String?
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(30))
            if board.changeCount != before {
                text = board.string(forType: .string)
                break
            }
        }
        if let saved, board.changeCount != before {
            board.clearContents()
            board.writeObjects(saved.map { entries in
                let item = NSPasteboardItem()
                entries.forEach { item.setData($0.1, forType: $0.0) }
                return item
            })
        }
        return text
    }

    private static func send(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
