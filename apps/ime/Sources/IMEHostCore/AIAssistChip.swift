import AppKit
import UserData

/// The ✨ suggestion after a sentence (proof of concept: 转成英文 only). When a sentence qualifies in
/// an app the user enabled, it is sent to the AI right away, so the result is usually ready by the
/// time the user looks at the chip. `Tab` replaces the sentence (or does so as soon as the result
/// arrives); `Esc` dismisses; any other key dismisses and is typed normally.
@MainActor
final class AIAssistChipController {
    struct Offer {
        let app: String
        let sentence: String
        /// The sentence's range in the client, valid while the cursor has not moved.
        let range: NSRange
        let caret: CGRect
        /// Replaces the range with the text; returns false when the app did not take it.
        let apply: (String, NSRange) -> Bool
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
    private let now: () -> Date
    private let hideAfter: (TimeInterval, @escaping @MainActor () -> Void) -> Void

    var isShowing: Bool { display != nil }

    init(
        rewriter: @escaping () -> AIRewriter?,
        present: @escaping (Display?, CGRect) -> Void,
        now: @escaping () -> Date = { Date() },
        hideAfter: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
        }
    ) {
        self.rewriter = rewriter
        self.present = present
        self.now = now
        self.hideAfter = hideAfter
    }

    /// A finished sentence worth offering: ends with sentence punctuation, 6+ characters, and mostly
    /// Chinese, weighing Han characters against English words ("加一个 timeout" is Chinese).
    nonisolated static func qualifies(_ sentence: String) -> Bool {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 6, let last = text.last, SentenceAssembler.enders.contains(last) else {
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
        dismiss()
        lastOffer[offer.app] = time
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

    func handleKey(_ keyCode: UInt16) -> KeyOutcome? {
        guard let display else {
            return nil
        }
        switch keyCode {
        case Self.tabKey:
            switch display {
            case .ready:
                applyResult()
            case .generating:
                accepted = true
                show(.generating(accepted: true))
            case .done, .failed:
                dismiss()
            }
            return .consumed
        case Self.escapeKey:
            dismiss()
            return .consumed
        default:
            dismiss()
            return .passThrough
        }
    }

    /// Hides the chip and stops the request if it is still running.
    func dismiss() {
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
        switch outcome {
        case .success(let text):
            result = text
            if accepted {
                applyResult()
            } else {
                show(.ready(preview: text))
                hideLater()
            }
        case .failure(let error):
            show(.failed(error.message))
            hideLater()
        }
    }

    private func applyResult() {
        guard let offer, let result else {
            return
        }
        let replaced = offer.apply(result, offer.range)
        show(.done(replaced ? "已替换" : "这个应用不支持替换，已复制，⌘V 粘贴"))
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
            self.dismiss()
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
        case .generating(let accepted): text = accepted ? "✨ 转成英文 · 生成中，好了自动替换…" : "✨ 转成英文 · 生成中…   ⇥"
        case .ready(let preview): text = "✨ \(preview)   ⇥ 替换"
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
