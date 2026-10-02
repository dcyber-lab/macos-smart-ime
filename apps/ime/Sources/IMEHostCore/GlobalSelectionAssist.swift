import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Rewrite, translate, or explain text where no text field has focus (a web page, a PDF, a read-only
/// view), where the input method gets no key events. A system hotkey (⌃⌥E, no permission needed) starts
/// the same popup. The text is the selection copied with ⌘C when Accessibility access is granted, else
/// whatever is on the clipboard (select, press ⌘C, then the hotkey). The result is copied, never pasted
/// into the page.
@MainActor
public final class GlobalSelectionAssist {
    public static let shared = GlobalSelectionAssist()

    private var hotKeyRef: EventHotKeyRef?
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

    public func install() {
        guard hotKeyRef == nil else {
            return
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in
                GlobalSelectionAssist.shared.startReadOnly()
            }
            return noErr
        }, 1, &spec, nil, nil)
        let hotkey = AIAssistSettings().readHotkey
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
        where hotkey.modifiers.contains(flag) {
            modifiers |= UInt32(carbon)
        }
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode), modifiers, EventHotKeyID(signature: OSType(0x534D4149), id: 1),
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        TranslationPopup.shared.keyHandler = { [weak self] keyCode in
            self?.handlePopupKey(keyCode)
        }
        TranslationPopup.shared.dismissHandler = { [weak self] in
            self?.controller.dismiss()
        }
        log("global hotkey: registered (status \(status)), accessibility=\(WindowTitleReader.isTrusted)")
    }

    private func log(_ event: String) {
        AIAssistEventLog.shared.append(event, app: "-")
    }

    /// Also used by the input method when the focused page reports no text of its own; it passes
    /// `clipboardFallback: false`, since ⌃⌥R means the selection, not what was copied earlier.
    func startReadOnly(clipboardFallback: Bool = true) {
        guard !IsSecureEventInputEnabled() else {
            return
        }
        log(clipboardFallback ? "global hotkey: pressed" : "global hotkey: started by the input method")
        Task { @MainActor in
            await self.start(clipboardFallback: clipboardFallback)
        }
    }

    private func start(clipboardFallback: Bool) async {
        let mouse = NSEvent.mouseLocation
        anchor = CGRect(x: mouse.x, y: mouse.y - 6, width: 1, height: 6)
        previousApp = NSWorkspace.shared.frontmostApplication
        var text: String?
        if WindowTitleReader.isTrusted {
            text = await SelectionCopier.copySelection()
        }
        let copied = text != nil
        if text == nil, clipboardFallback {
            text = NSPasteboard.general.string(forType: .string)
        }
        log("global hotkey: \(text?.count ?? 0) characters, \(copied ? "copied selection" : clipboardFallback ? "clipboard" : "nothing copied")")
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
