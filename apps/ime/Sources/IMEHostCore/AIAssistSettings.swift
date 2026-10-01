import Foundation

/// AI assist settings in the input method's defaults domain, read on use.
struct AIAssistSettings {
    static let chipAppsKey = "AIAssistChipApps"
    static let codexPathKey = "AICodexPath"
    static let codexModelKey = "AICodexModel"
    static let codexEffortKey = "AICodexReasoningEffort"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Apps where sentences may be sent ahead to the AI so a suggestion is ready; none by default.
    var chipApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.chipAppsKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Self.chipAppsKey) }
    }

    func toggleChips(in app: String) {
        chipApps = chipApps.symmetricDifference([app])
    }

    var codexPath: String? { defaults.string(forKey: Self.codexPathKey) }
    var codexModel: String { defaults.string(forKey: Self.codexModelKey) ?? "gpt-6-luna" }
    var codexReasoningEffort: String { defaults.string(forKey: Self.codexEffortKey) ?? "low" }

    /// Nil when Codex is not installed.
    func rewriter() -> CodexRewriter? {
        CodexRewriter.locate(configured: codexPath).map {
            CodexRewriter(executableURL: $0, model: codexModel, reasoningEffort: codexReasoningEffort)
        }
    }
}
