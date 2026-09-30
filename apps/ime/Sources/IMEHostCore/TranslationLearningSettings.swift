import Foundation

/// Translation learning settings in the input method's defaults domain, read on every use so that
/// `defaults write lab.dcyber.inputmethod.smartime …` applies without restarting the input method.
struct TranslationLearningSettings {
    static let enabledKey = "TranslationLearningEnabled"
    static let intervalKey = "TranslationLearningInterval"
    static let defaultInterval: TimeInterval = 24 * 60 * 60
    static let minimumInterval: TimeInterval = 60

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off stops both counting commits and translating.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Seconds between learning runs.
    var interval: TimeInterval {
        max(Self.minimumInterval, (defaults.object(forKey: Self.intervalKey) as? NSNumber)?.doubleValue ?? Self.defaultInterval)
    }
}
