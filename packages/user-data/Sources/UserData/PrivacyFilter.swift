import Foundation

/// Decides what the intelligence hub may learn. Rules apply before anything is derived or journaled,
/// and a sentence that breaks one is dropped whole rather than masked.
public enum PrivacyFilter {
    /// Password managers and terminals, which hold secrets and commands.
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
    ]

    private static let sensitivePatterns = [
        // Verification codes, phone, card, and ID numbers.
        #"\d{6,}"#,
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        #"(?i)\b(?:https?://|www\.)\S+"#,
        // API keys and other tokens: long runs that mix letters and digits.
        #"(?=[A-Za-z0-9_-]*[0-9])(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{20,}"#,
    ]

    public static func allowsSentence(_ sentence: String) -> Bool {
        !sensitivePatterns.contains { sentence.range(of: $0, options: .regularExpression) != nil }
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
