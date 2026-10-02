import Foundation

/// AI assist settings in the input method's defaults domain, read on use.
struct AIAssistSettings {
    static let chipAppsKey = "AIAssistChipApps"
    static let providerKey = "AIProvider"
    static let hotkeyKey = "AIAssistHotkey"
    /// ⌃⌥R: R is ANSI key code 15.
    static let defaultHotkey = TranslationHotkey(keyCode: 15, modifiers: [.control, .option])
    static let codexPathKey = "AICodexPath"
    static let codexModelKey = "AICodexModel"
    static let codexEffortKey = "AICodexReasoningEffort"

    /// Where rewrites run. `auto` prefers Apple Intelligence (on the Mac, fast, free) and falls back to Codex.
    enum Provider: String, CaseIterable {
        case auto
        case apple
        case codex

        var title: String {
            switch self {
            case .auto: "模型：自动（优先本机）"
            case .apple: "模型：Apple Intelligence（本机）"
            case .codex: "模型：Codex（会发给 OpenAI）"
            }
        }
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Apps where finished sentences are rewritten ahead so a suggestion is ready; none by default.
    var chipApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.chipAppsKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Self.chipAppsKey) }
    }

    func toggleChips(in app: String) {
        chipApps = chipApps.symmetricDifference([app])
    }

    /// The rewrite hotkey, as `modifier+…+letter` like the translation hotkey; default ⌃⌥R.
    var hotkey: TranslationHotkey {
        defaults.string(forKey: Self.hotkeyKey).flatMap(TranslationHotkey.init(string:)) ?? Self.defaultHotkey
    }

    var provider: Provider {
        get { defaults.string(forKey: Self.providerKey).flatMap(Provider.init(rawValue:)) ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.providerKey) }
    }

    var codexPath: String? { defaults.string(forKey: Self.codexPathKey) }
    var codexModel: String { defaults.string(forKey: Self.codexModelKey) ?? "gpt-6-luna" }
    var codexReasoningEffort: String { defaults.string(forKey: Self.codexEffortKey) ?? "low" }

    /// Which provider rewrites would use now, or nil when none can run. `appleAvailable` and
    /// `codexFound` are injectable for tests (the CI runner has neither).
    func activeProvider(appleAvailable: Bool? = nil, codexFound: Bool? = nil) -> Provider? {
        let apple = appleAvailable ?? Self.isAppleAvailable
        let codex = codexFound ?? (codexRewriter() != nil)
        switch provider {
        case .apple: return apple ? .apple : nil
        case .codex: return codex ? .codex : nil
        case .auto: return apple ? .apple : (codex ? .codex : nil)
        }
    }

    /// The rewriter for the active provider, or nil when none can run.
    func rewriter() -> AIRewriter? {
        switch activeProvider() {
        case .apple: Self.appleRewriter()
        case .codex: codexRewriter()
        case .auto, nil: nil
        }
    }

    func codexRewriter() -> CodexRewriter? {
        CodexRewriter.locate(configured: codexPath).map {
            CodexRewriter(executableURL: $0, model: codexModel, reasoningEffort: codexReasoningEffort)
        }
    }

    static var isAppleAvailable: Bool {
        if #available(macOS 26.0, *) {
            return AppleRewriter.isAvailable
        }
        return false
    }

    private static func appleRewriter() -> AIRewriter? {
        if #available(macOS 26.0, *) {
            return AppleRewriter()
        }
        return nil
    }
}
