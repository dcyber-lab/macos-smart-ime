import Foundation
import UserData

/// ⌃⌥R: rewrite the selection, or the line before the cursor, with AI. The popup lists the actions,
/// shows the request running, then the result; `Return` replaces the text, `Esc` keeps it. Nothing is
/// sent until the user picks an action.
@MainActor
final class AIRewriteController {
    enum State: Equatable {
        case idle
        /// `truncated`: the app reported only the end of a long line; selecting it gets all of it.
        case choosing(text: String, defaultAction: AIAction, truncated: Bool)
        case running(action: AIAction, text: String)
        case result(action: AIAction, original: String, rewritten: String)
        case message(String)
    }

    enum KeyOutcome: Equatable {
        case replace(String, NSRange)
        /// Read-only mode (no text field): the result is copied instead of replacing anything.
        case copy(String)
        /// `consumed` is false when the key should still be handled as normal input.
        case dismissed(consumed: Bool)
        case handled
    }

    /// Number keys 1–7 (ANSI key codes) pick the actions in `AIAction.allCases` order.
    static let actionKeys: [UInt16: AIAction] = Dictionary(uniqueKeysWithValues: zip([18, 19, 20, 21, 23, 22, 26], AIAction.allCases))
    private static let returnKeys: Set<UInt16> = [36, 76]
    private static let escapeKey: UInt16 = 53

    private(set) var state = State.idle {
        didSet {
            present(state)
            if case .message = state {
                dismissMessageLater()
            }
        }
    }
    private let rewriter: () -> AIRewriter?
    private let present: @MainActor (State) -> Void
    private let messageLifetime: Duration
    private var range = NSRange(location: NSNotFound, length: 0)
    private var task: Task<Void, Never>?
    private var requestID = 0
    /// True when the text is not in a text field (a web page): results are copied, never replaced.
    private(set) var readOnly = false

    init(rewriter: @escaping () -> AIRewriter?, messageLifetime: Duration = .seconds(6), present: @escaping @MainActor (State) -> Void) {
        self.rewriter = rewriter
        self.messageLifetime = messageLifetime
        self.present = present
    }

    var isActive: Bool {
        state != .idle
    }

    /// Chinese text defaults to 转成英文, anything else to 润色.
    nonisolated static func defaultAction(for text: String, readOnly: Bool = false) -> AIAction {
        let (han, english) = InputMemory.languageCounts(text)
        if han > 0 && Double(han) / Double(han + english) >= 0.5 {
            return .toEnglish
        }
        // A word or short phrase of English is most likely something to look up.
        let words = text.split { $0.isWhitespace }.count
        if han == 0 && english > 0 && words <= 4 {
            return .explain
        }
        // Reading, not writing: a long English text is most likely wanted in Chinese.
        return readOnly && han == 0 ? .toChinese : .polish
    }

    /// `text` is nil when the app does not report its text.
    func start(text: String?, range: NSRange, truncated: Bool = false, readOnly: Bool = false) {
        cancel()
        self.readOnly = readOnly
        self.range = range
        guard let text else {
            state = .message(readOnly ? "没有读到选中的文字：先选中，再按 ⌃⌥R" : "这个应用不提供文字给输入法，先选中文字再按 ⌃⌥R")
            return
        }
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            state = .message("没有可改写的文字：先选中，或把光标放在要改写的这一行末尾")
            return
        }
        guard rewriter() != nil else {
            state = .message("没有可用的模型：打开 Apple Intelligence 或安装 Codex")
            return
        }
        state = .choosing(text: source, defaultAction: Self.defaultAction(for: source, readOnly: readOnly), truncated: truncated)
    }

    func handleKey(_ keyCode: UInt16) -> KeyOutcome {
        switch state {
        case .idle:
            return .dismissed(consumed: false)
        case .choosing(let text, let defaultAction, _):
            if let action = Self.actionKeys[keyCode] {
                run(action, on: text)
                return .handled
            }
            if Self.returnKeys.contains(keyCode) {
                run(defaultAction, on: text)
                return .handled
            }
        case .running:
            if Self.returnKeys.contains(keyCode) {
                return .handled
            }
        case .result(let action, _, let rewritten):
            if Self.returnKeys.contains(keyCode) {
                let range = self.range
                dismiss()
                // An explanation is for reading; it never replaces the selected text.
                if readOnly {
                    return .copy(rewritten)
                }
                return action == .explain ? .dismissed(consumed: true) : .replace(rewritten, range)
            }
        case .message:
            break
        }
        let consumed = Self.returnKeys.contains(keyCode) || keyCode == Self.escapeKey || Self.actionKeys[keyCode] != nil
        dismiss()
        return .dismissed(consumed: consumed)
    }

    func dismiss() {
        cancel()
        if state != .idle {
            state = .idle
        }
    }

    private func run(_ action: AIAction, on text: String) {
        guard let rewriter = rewriter() else {
            state = .message("没有可用的模型：打开 Apple Intelligence 或安装 Codex")
            return
        }
        requestID += 1
        let request = requestID
        state = .running(action: action, text: text)
        task = Task { [weak self] in
            let next: State
            do {
                let rewritten = try await rewriter.rewrite(text, action: action)
                next = .result(action: action, original: text, rewritten: rewritten)
            } catch is CancellationError {
                return
            } catch {
                next = .message((error as? AIError)?.message ?? error.localizedDescription)
            }
            // A dismissed or newer request makes this result stale.
            guard let self, request == self.requestID, case .running = self.state else {
                return
            }
            self.state = next
        }
    }

    /// A message needs no key to go away: the popup may be over an app that sends no keys to the input method.
    private func dismissMessageLater() {
        let shown = state
        let lifetime = messageLifetime
        Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            if let self, self.state == shown {
                self.state = .idle
            }
        }
    }

    private func cancel() {
        requestID += 1
        task?.cancel()
        task = nil
    }
}
