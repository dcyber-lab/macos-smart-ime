import Foundation
import Translation

enum SelectionTranslationError: Error, Equatable {
    case modelNotInstalled(TranslationDirection)
    case languagePairUnsupported
    case requiresNewerSystem
    case failed(String)
}

protocol SelectionTranslator: Sendable {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String
}

/// English <-> Simplified Chinese with Apple's on-device Translation framework.
struct AppleSelectionTranslator: SelectionTranslator {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw SelectionTranslationError.requiresNewerSystem
        }

        let source = direction.source
        let target = direction.target
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw SelectionTranslationError.modelNotInstalled(direction)
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

/// Translates the client's selection on a hotkey (direction detected from the text), shows the result,
/// and replaces the selection on Return.
@MainActor
final class SelectionTranslationController {
    enum State: Equatable {
        case idle
        case translating(source: String, direction: TranslationDirection)
        case result(source: String, translation: String, direction: TranslationDirection)
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
            state = .message("The current app did not provide the selected text")
            return
        }
        let source = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            state = .message("Select the English text to translate first")
            return
        }

        let direction = TranslationDirection.detect(source)
        state = .translating(source: source, direction: direction)
        let request = requestID
        Task { [translator] in
            let next: State
            do {
                let translation = try await translator.translate(source, direction: direction)
                next = .result(source: source, translation: translation, direction: direction)
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
        if Self.returnKeys.contains(keyCode), case .result(_, let translation, _) = state {
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
        case .modelNotInstalled(let direction):
            return "Download the translation languages first: System Settings › General › Language & Region › Translation Languages, add \(direction.languageNames)"
        case .languagePairUnsupported:
            return "The system does not support translating between these languages"
        case .requiresNewerSystem:
            return "Translating a selection requires macOS 26"
        case .failed(let reason):
            return "Translation failed: \(reason)"
        case nil:
            return "Translation failed: \(error.localizedDescription)"
        }
    }
}
