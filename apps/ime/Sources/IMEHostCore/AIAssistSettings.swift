import Foundation

/// AI assist settings in the input method's defaults domain, read on use.
struct AIAssistSettings {
    static let chipAppsKey = "AIAssistChipApps"
    static let providerKey = "AIProvider"
    static let hotkeyKey = "AIAssistHotkey"
    /// ⌃⌥R: R is ANSI key code 15.
    static let defaultHotkey = TranslationHotkey(keyCode: 15, modifiers: [.control, .option])
    static let readHotkeyKey = "AIReadHotkey"
    /// ⌃⌥E for text outside text fields (E is ANSI key code 14); ⌃⌥R is taken by the input method inside them.
    static let defaultReadHotkey = TranslationHotkey(keyCode: 14, modifiers: [.control, .option])
    static let codexPathKey = "AICodexPath"
    static let codexModelKey = "AICodexModel"
    static let codexEffortKey = "AICodexReasoningEffort"
    static let ollamaURLKey = "AIOllamaURL"
    static let ollamaModelKey = "AIOllamaModel"

    /// Where rewrites run. `auto` prefers a local Ollama model, then Apple Intelligence (both on the Mac, free), then Codex.
    enum Provider: String, CaseIterable {
        case auto
        case ollama
        case apple
        case codex

        var title: String {
            switch self {
            case .auto: "Auto (prefer on-device)"
            case .ollama: "Ollama (on-device)"
            case .apple: "Apple Intelligence (on-device)"
            case .codex: "Codex (sent to OpenAI)"
            }
        }
    }

    /// What rewrites use now and whether text leaves the Mac; `active` comes from `activeProvider()`.
    static func statusText(_ active: Provider?, codexModel: String, ollamaModel: String = OllamaRewriter.defaultModel) -> String {
        switch active {
        case .ollama: "Current: Ollama (\(ollamaModel)), runs on this Mac, nothing is sent out"
        case .apple: "Current: Apple Intelligence, runs on this Mac, nothing is sent out"
        case .codex: "Current: Codex (\(codexModel)), sentences in apps with AI hints on are sent to OpenAI"
        case .auto, nil: "Current: no model available (start Ollama, turn on Apple Intelligence, or install Codex)"
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

    var readHotkey: TranslationHotkey {
        defaults.string(forKey: Self.readHotkeyKey).flatMap(TranslationHotkey.init(string:)) ?? Self.defaultReadHotkey
    }

    var provider: Provider {
        get { defaults.string(forKey: Self.providerKey).flatMap(Provider.init(rawValue:)) ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.providerKey) }
    }

    var codexPath: String? { defaults.string(forKey: Self.codexPathKey) }
    var codexModel: String { defaults.string(forKey: Self.codexModelKey) ?? "gpt-6-luna" }
    var codexReasoningEffort: String { defaults.string(forKey: Self.codexEffortKey) ?? "low" }

    var ollamaURL: URL { defaults.string(forKey: Self.ollamaURLKey).flatMap(URL.init(string:)) ?? URL(string: OllamaRewriter.defaultURL)! }
    var ollamaModel: String { defaults.string(forKey: Self.ollamaModelKey) ?? OllamaRewriter.defaultModel }

    /// Which provider rewrites would use now, or nil when none can run. `ollamaAvailable`,
    /// `appleAvailable` and `codexFound` are injectable for tests (the CI runner has none of them).
    func activeProvider(ollamaAvailable: Bool? = nil, appleAvailable: Bool? = nil, codexFound: Bool? = nil) -> Provider? {
        let ollama = ollamaAvailable ?? OllamaRewriter.isAvailable(baseURL: ollamaURL, model: ollamaModel)
        let apple = appleAvailable ?? Self.isAppleAvailable
        let codex = codexFound ?? (codexRewriter() != nil)
        switch provider {
        case .ollama: return ollama ? .ollama : nil
        case .apple: return apple ? .apple : nil
        case .codex: return codex ? .codex : nil
        case .auto: return ollama ? .ollama : (apple ? .apple : (codex ? .codex : nil))
        }
    }

    /// The rewriter for the active provider, or nil when none can run.
    func rewriter() -> AIRewriter? {
        switch activeProvider() {
        case .ollama: OllamaRewriter(baseURL: ollamaURL, model: ollamaModel)
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
