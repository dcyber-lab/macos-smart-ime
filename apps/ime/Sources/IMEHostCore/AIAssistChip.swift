import AppKit
import UserData

/// The ✨ suggestion after a sentence (proof of concept: 转成英文 only). When a sentence qualifies in
/// an app the user enabled, it is sent to the AI right away, so the result is usually ready by the
/// time the user looks at the chip. `Tab` or `→` replaces the sentence (or does so as soon as the
/// result arrives); `Esc` dismisses; any other key dismisses and is typed normally. `→` is there
/// because some apps (Sublime Text) keep `Tab` for themselves and never pass it to the input method.
@MainActor
final class AIAssistChipController {
    struct Offer {
        let app: String
        let sentence: String
        /// The sentence's range in the client, valid while the cursor has not moved.
        let range: NSRange
        let caret: CGRect
        /// Replaces the range with the text if it still holds the sentence.
        let apply: (String, NSRange) -> AIReplacement
    }

    enum Display: Equatable {
        case generating(accepted: Bool)
        case ready(preview: String)
        case done(String)
        case failed(String)
    }

    enum KeyOutcome: Equatable {
        case consumed
        case passThrough
    }

    /// Keeps chips from flickering over consecutive sentences; a dismissed chip does not block the next one.
    static let minimumInterval: TimeInterval = 5
    static let lifetime: TimeInterval = 8
    static let tabKey: UInt16 = 48
    static let rightArrowKey: UInt16 = 124
    static let escapeKey: UInt16 = 53

    private(set) var display: Display?
    private var offer: Offer?
    private var result: String?
    private var accepted = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private var lastOffer: [String: Date] = [:]
    private let rewriter: () -> AIRewriter?
    private let present: (Display?, CGRect) -> Void
    /// Records what happened (event, app), never text, so a failed try can be explained.
    private let log: (String, String) -> Void
    private var offeredAt = Date.distantPast
    private let now: () -> Date
    private let hideAfter: (TimeInterval, @escaping @MainActor () -> Void) -> Void

    var isShowing: Bool { display != nil }

    init(
        rewriter: @escaping () -> AIRewriter?,
        present: @escaping (Display?, CGRect) -> Void,
        log: @escaping (String, String) -> Void = { _, _ in },
        now: @escaping () -> Date = { Date() },
        hideAfter: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
        }
    ) {
        self.rewriter = rewriter
        self.present = present
        self.log = log
        self.now = now
        self.hideAfter = hideAfter
    }

    /// A finished sentence worth offering: ends with sentence punctuation, 5+ characters, and mostly
    /// Chinese, weighing Han characters against English words ("加一个 timeout" is Chinese).
    nonisolated static func qualifies(_ sentence: String) -> Bool {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 5, let last = text.last, SentenceAssembler.enders.contains(last) else {
            return false
        }
        let (han, english) = InputMemory.languageCounts(text)
        return han > 0 && Double(han) / Double(han + english) >= 0.7
    }

    /// Starts the rewrite and shows the chip, unless this app had an offer within `minimumInterval`.
    func offer(_ offer: Offer) {
        let time = now()
        if let last = lastOffer[offer.app], time.timeIntervalSince(last) < Self.minimumInterval {
            return
        }
        guard let rewriter = rewriter() else {
            return
        }
        dismiss(reason: nil)
        lastOffer[offer.app] = time
        offeredAt = time
        log("offered", offer.app)
        self.offer = offer
        generation += 1
        let current = generation
        show(.generating(accepted: false))
        let sentence = offer.sentence
        task = Task { [weak self] in
            do {
                let text = try await rewriter.rewrite(sentence, action: .toEnglish)
                self?.finished(.success(text), generation: current)
            } catch is CancellationError {
            } catch {
                self?.finished(.failure(error as? AIError ?? .failed(error.localizedDescription)), generation: current)
            }
        }
    }

    /// Only a bare `Tab` or `→` accepts: with a modifier they move or select (⇧→, ⌥→, ⌘→), so they dismiss
    /// like other keys. Once only a message is left, they are the app's again.
    func handleKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> KeyOutcome? {
        guard let display else {
            return nil
        }
        let bare = modifiers.isDisjoint(with: [.shift, .control, .option, .command])
        switch keyCode {
        case Self.tabKey where bare, Self.rightArrowKey where bare:
            switch display {
            case .ready:
                applyResult()
            case .generating:
                accepted = true
                log("accepted early", offer?.app ?? "")
                show(.generating(accepted: true))
            case .done, .failed:
                dismiss(reason: nil)
                return .passThrough
            }
            return .consumed
        case Self.escapeKey:
            dismiss(reason: "dismissed by Esc")
            return .consumed
        default:
            dismiss(reason: "dismissed by key \(keyCode)")
            return .passThrough
        }
    }

    /// Hides the chip and stops the request if it is still running.
    func dismiss(reason: String? = "dismissed") {
        if let reason, let app = offer?.app {
            log(reason, app)
        }
        task?.cancel()
        task = nil
        offer = nil
        result = nil
        accepted = false
        generation += 1
        display = nil
        present(nil, .zero)
    }

    private func finished(_ outcome: Result<String, AIError>, generation current: Int) {
        guard current == generation else {
            return
        }
        task = nil
        let app = offer?.app ?? ""
        let seconds = String(format: "%.1fs", now().timeIntervalSince(offeredAt))
        switch outcome {
        case .success(let text):
            log("ready after \(seconds)", app)
            result = text
            if accepted {
                applyResult()
            } else {
                show(.ready(preview: text))
                hideLater()
            }
        case .failure(let error):
            log("failed after \(seconds): \(error)", app)
            show(.failed(error.message))
            hideLater()
        }
    }

    private func applyResult() {
        guard let offer, let result else {
            return
        }
        let outcome = offer.apply(result, offer.range)
        log(outcome.event, offer.app)
        show(.done(outcome.message))
        self.result = nil
        self.offer = nil
        hideLater(after: 1.5)
    }

    private func show(_ display: Display) {
        self.display = display
        present(display, offer?.caret ?? .zero)
    }

    private func hideLater(after delay: TimeInterval = AIAssistChipController.lifetime) {
        let current = generation
        hideAfter(delay) { [weak self] in
            guard let self, self.generation == current, self.display != nil else { return }
            self.dismiss(reason: "timed out")
        }
    }
}

/// What happened when an AI result was put back into the app. Unless it was replaced, the result is on the clipboard.
enum AIReplacement: Equatable {
    case replaced
    /// The app did not take the replacement.
    case refused
    /// The text in the range is no longer what was read (edited, or the cursor went elsewhere), so nothing was replaced.
    case textChanged

    var message: String {
        switch self {
        case .replaced: "已替换"
        case .refused: "这个应用不支持替换，已复制，⌘V 粘贴"
        case .textChanged: "原文已改动，没有替换，已复制，⌘V 粘贴"
        }
    }

    /// For the event log, which never holds text.
    var event: String {
        switch self {
        case .replaced: "replaced"
        case .refused: "replacement refused, copied"
        case .textChanged: "text changed, copied"
        }
    }
}

/// The chip's window: a single line in the candidate panel's style, just below the caret.
@MainActor
final class SuggestionChip {
    static let shared = SuggestionChip()

    private let window: NSPanel
    private let label = NSTextField(labelWithString: "")
    private static let maxWidth: CGFloat = 460

    private init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.maskImage = CandidatePanel.roundedMask(radius: 10)
        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        background.addSubview(label)
        window.contentView = background
    }

    func show(_ display: AIAssistChipController.Display?, caret: CGRect) {
        guard let display else {
            window.orderOut(nil)
            return
        }
        let text: String
        switch display {
        case .generating(let accepted): text = accepted ? "✨ 转成英文 · 生成中，好了自动替换…" : "✨ 转成英文 · 生成中…   Tab / → 好了就替换"
        case .ready(let preview): text = "✨ \(preview)   Tab / → 替换 · Esc 关闭"
        case .done(let message): text = "✨ \(message)"
        case .failed(let message): text = "✨ \(message)"
        }
        label.stringValue = text
        label.textColor = .labelColor
        let size = label.fittingSize
        let width = min(ceil(size.width) + 24, Self.maxWidth)
        let frameSize = CGSize(width: width, height: ceil(size.height) + 14)
        label.frame = CGRect(x: 12, y: 7, width: width - 24, height: ceil(size.height))
        let screen = NSScreen.screens.first { $0.frame.contains(caret.origin) } ?? NSScreen.main
        let origin = CandidatePanelPlacement.origin(panelSize: frameSize, caretRect: caret,
                                                    visibleFrame: screen?.visibleFrame ?? CGRect(origin: .zero, size: frameSize))
        window.setFrame(CGRect(origin: origin, size: frameSize), display: true)
        window.contentView?.frame = CGRect(origin: .zero, size: frameSize)
        window.invalidateShadow()
        window.orderFrontRegardless()
    }
}
