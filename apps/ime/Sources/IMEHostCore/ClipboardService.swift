import AppKit

/// Clipboard history from anywhere: watches the pasteboard while enabled and opens the history panel from
/// a system hotkey (⌃⌥V). Everything stays on this Mac. Pasting into the app in front needs Accessibility
/// access (it sends ⌘V); without it the choice is only copied.
@MainActor
public final class ClipboardService {
    public static let shared = ClipboardService()

    let store = ClipboardHistoryStore(directory: IMEHostConfiguration.clipboardHistoryDirectoryURL())
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var registered: TranslationHotkey?
    private var panel: ClipboardPanel?

    private init() {}

    public func install() {
        refresh()
        // The service lives as long as the process, so the observer is never removed.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ClipboardService.shared.refresh() }
        }
    }

    func refresh() {
        let settings = ClipboardSettings()
        store.retentionDays = settings.retentionDays
        guard settings.isEnabled else {
            timer?.invalidate()
            timer = nil
            if registered != nil {
                registered = nil
                GlobalHotkeys.shared.unregister(.clipboard)
            }
            return
        }
        if timer == nil {
            lastChangeCount = NSPasteboard.general.changeCount
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                MainActor.assumeIsolated { ClipboardService.shared.poll() }
            }
            store.prune()
        }
        if registered != settings.hotkey {
            registered = settings.hotkey
            GlobalHotkeys.shared.register(settings.hotkey, id: .clipboard) {
                ClipboardService.shared.togglePanel()
            }
        }
    }

    // MARK: Recording

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = board.changeCount
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard ClipboardSettings.allowsCopy(from: app, types: (board.types ?? []).map(\.rawValue)) else {
            return
        }
        if let text = board.string(forType: .string) {
            store.addText(text, app: app)
        } else if ClipboardSettings().keepsImages, let image = Self.pngImage(from: board) {
            store.addImage(png: image.data, width: image.width, height: image.height, app: app)
        }
    }

    private static func pngImage(from board: NSPasteboard) -> (data: Data, width: Int, height: Int)? {
        let source = board.data(forType: .png) ?? board.data(forType: .tiff)
        guard let source, let rep = NSBitmapImageRep(data: source) else {
            return nil
        }
        let data = board.data(forType: .png) ?? rep.representation(using: .png, properties: [:])
        return data.map { ($0, rep.pixelsWide, rep.pixelsHigh) }
    }

    // MARK: Panel

    func togglePanel() {
        if let panel, panel.isVisible {
            panel.close()
            return
        }
        let panel = panel ?? ClipboardPanel(store: store) { [weak self] item in self?.paste(item) }
        self.panel = panel
        panel.show()
    }

    private func paste(_ item: ClipboardItem) {
        let board = NSPasteboard.general
        board.clearContents()
        switch item.kind {
        case .text:
            board.setString(item.text ?? "", forType: .string)
        case .image:
            guard let url = store.imageURL(for: item), let data = try? Data(contentsOf: url) else {
                ScreenshotToast.show("这张图片已经不在了")
                return
            }
            board.setData(data, forType: .png)
        }
        guard WindowTitleReader.isTrusted else {
            ScreenshotToast.show("已复制，按 ⌘V 粘贴")
            return
        }
        // Let the panel hand the keyboard back and the hotkey's modifiers come up first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
