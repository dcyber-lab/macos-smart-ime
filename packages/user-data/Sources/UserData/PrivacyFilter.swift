import Foundation

/// Decides what the intelligence hub may learn. App rules decide whether anything is recorded; text
/// rules mask sensitive spans before anything is derived or journaled.
public enum PrivacyFilter {
    /// Password managers and terminals, which hold secrets and commands, and launchers, whose
    /// search terms are not sentences.
    public static let defaultExcludedApps: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "com.runningwithcrayons.Alfred",
        "com.raycast.macos",
        "com.apple.Spotlight",
        "at.obdev.LaunchBar",
    ]

    /// Sensitive spans and what replaces them, applied in this order (a URL may contain a token).
    private static let masks: [(pattern: String, placeholder: String)] = [
        (#"(?i)\b(?:https?://|www\.)\S+"#, "〔链接〕"),
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "〔邮箱〕"),
        // API keys and other tokens: long runs that mix letters and digits.
        (#"(?=[A-Za-z0-9_-]*[0-9])(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{20,}"#, "〔密钥〕"),
        // Verification codes, phone, card, and ID numbers.
        (#"\d{6,}"#, "〔数字〕"),
    ]

    /// The text with URLs, email addresses, tokens, and runs of 6+ digits replaced by placeholders, so
    /// the rest of a message is kept while those never reach the memory, the journal, or the page.
    public static func redact(_ text: String) -> String {
        masks.reduce(text) { $0.replacingOccurrences(of: $1.pattern, with: $1.placeholder, options: .regularExpression) }
    }

    /// True when nothing in the text would be masked.
    public static func allowsSentence(_ sentence: String) -> Bool {
        redact(sentence) == sentence
    }

    /// Apps without a bundle identifier are not learned. `userAllowed` lifts default exclusions the
    /// user chose to learn in anyway (e.g. a terminal used for chatting with an AI).
    public static func allowsApp(_ bundleIdentifier: String?, userExcluded: Set<String>, userAllowed: Set<String> = []) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return false
        }
        if userExcluded.contains(bundleIdentifier) {
            return false
        }
        return !defaultExcludedApps.contains(bundleIdentifier) || userAllowed.contains(bundleIdentifier)
    }
}
