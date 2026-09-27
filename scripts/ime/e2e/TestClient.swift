import AppKit

// Throwaway text client for the IME smoke test: one window, one text view, no documents or files
// except the state directory passed as the first argument. It writes the committed text (marked
// text excluded) to <state>/text.txt, the marked text to <state>/marked.txt, and creates
// <state>/ready once its window is key.

final class TestClientDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    private let stateDirectory: URL
    private var window: NSWindow!
    private var textView: NSTextView!
    private var lastWritten: String?
    private var lastMarked: String?

    init(stateDirectory: URL) {
        self.stateDirectory = stateDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "SmartIME 自动测试进行中：请勿操作键盘和鼠标"

        let scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as? NSTextView
        textView.font = .systemFont(ofSize: 18)
        textView.delegate = self
        // Keep the committed text exactly as the IME inserted it.
        textView.enabledTextCheckingTypes = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        window.contentView = scrollView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.publishState()
        }
    }

    func textDidChange(_ notification: Notification) {
        publishState()
    }

    private func publishState() {
        var committed = textView.string
        var marked = ""
        if textView.hasMarkedText(), let range = Range(textView.markedRange(), in: committed) {
            marked = String(committed[range])
            committed.removeSubrange(range)
        }
        if marked != lastMarked {
            lastMarked = marked
            try? marked.write(to: stateDirectory.appendingPathComponent("marked.txt"), atomically: true, encoding: .utf8)
        }
        if committed != lastWritten {
            lastWritten = committed
            try? committed.write(to: stateDirectory.appendingPathComponent("text.txt"), atomically: true, encoding: .utf8)
        }

        let ready = stateDirectory.appendingPathComponent("ready")
        if NSApp.isActive, window.isKeyWindow, !FileManager.default.fileExists(atPath: ready.path) {
            FileManager.default.createFile(atPath: ready.path, contents: nil)
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: SmartIMETestClient <state-directory>\n".data(using: .utf8)!)
    exit(2)
}
let app = NSApplication.shared
let delegate = TestClientDelegate(stateDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true))
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
