import Foundation
import Translation

enum SelectionTranslationError: Error, Equatable {
    case modelNotInstalled
    case languagePairUnsupported
    case requiresNewerSystem
    case failed(String)
}

protocol SelectionTranslator: Sendable {
    func translate(_ text: String) async throws -> String
}

/// English -> Simplified Chinese with Apple's on-device Translation framework.
struct AppleSelectionTranslator: SelectionTranslator {
    func translate(_ text: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw SelectionTranslationError.requiresNewerSystem
        }

        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw SelectionTranslationError.modelNotInstalled
        case .unsupported:
            throw SelectionTranslationError.languagePairUnsupported
        @unknown default:
            throw SelectionTranslationError.languagePairUnsupported
        }

        do {
            return try await TranslationSession(installedSource: source, target: target).translate(text).targetText
        } catch {
            throw SelectionTranslationError.failed(error.localizedDescription)
        }
    }
}

/// POC: translate the client's selection on a hotkey, show the result, replace it on Return.
@MainActor
final class SelectionTranslationController {
    enum State: Equatable {
        case idle
        case translating(source: String)
        case result(source: String, translation: String)
        case message(String)
    }

    enum KeyOutcome: Equatable, Sendable {
        case replace(String, NSRange)
        /// `consumed` is false when the key should still be handled as normal input.
        case dismissed(consumed: Bool)
    }

    private static let returnKeys: Set<UInt16> = [36, 76]
    private static let escapeKey: UInt16 = 53

    private(set) var state = State.idle {
        didSet { present(state) }
    }
    private let translator: SelectionTranslator
    private let present: @MainActor (State) -> Void
    private var selectedRange = NSRange(location: NSNotFound, length: 0)
    private var requestID = 0

    init(translator: SelectionTranslator, present: @escaping @MainActor (State) -> Void) {
        self.translator = translator
        self.present = present
    }

    var isActive: Bool {
        state != .idle
    }

    /// `selectedText` is nil when the client does not report its selection.
    func start(selectedText: String?, range: NSRange) {
        requestID += 1
        selectedRange = range
        guard let selectedText else {
            state = .message("当前应用没有提供选中的文字")
            return
        }
        let source = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            state = .message("请先选中要翻译的英文")
            return
        }

        state = .translating(source: source)
        let request = requestID
        Task { [translator] in
            let next: State
            do {
                next = .result(source: source, translation: try await translator.translate(source))
            } catch {
                next = .message(Self.message(for: error))
            }
            // A dismissed or newer request makes this result stale.
            guard request == self.requestID, case .translating = self.state else {
                return
            }
            self.state = next
        }
    }

    func handleKey(_ keyCode: UInt16) -> KeyOutcome {
        if Self.returnKeys.contains(keyCode), case .result(_, let translation) = state {
            let range = selectedRange
            dismiss()
            return .replace(translation, range)
        }
        let consumed = Self.returnKeys.contains(keyCode) || keyCode == Self.escapeKey
        dismiss()
        return .dismissed(consumed: consumed)
    }

    func dismiss() {
        requestID += 1
        if state != .idle {
            state = .idle
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? SelectionTranslationError {
        case .modelNotInstalled:
            return "请先下载翻译语言：系统设置 › 通用 › 语言与地区 › 翻译语言，添加英语和简体中文"
        case .languagePairUnsupported:
            return "系统不支持英译中"
        case .requiresNewerSystem:
            return "整句翻译需要 macOS 26"
        case .failed(let reason):
            return "翻译失败：\(reason)"
        case nil:
            return "翻译失败：\(error.localizedDescription)"
        }
    }
}
