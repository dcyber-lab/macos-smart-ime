import CryptoKit
import Foundation

/// A salted hash that tells whether a sentence was typed before without keeping its text.
public enum SentenceFingerprint {
    /// Shorter sentences are too common and too easy to guess to be worth a fingerprint.
    public static let minimumLength = 6

    /// Trimmed, whitespace collapsed, Latin letters lowercased.
    public static func normalize(_ sentence: String) -> String {
        sentence
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Nil for sentences shorter than `minimumLength` after normalization.
    public static func make(_ sentence: String, salt: Data) -> String? {
        let normalized = normalize(sentence)
        guard normalized.count >= minimumLength else {
            return nil
        }
        let mac = HMAC<SHA256>.authenticationCode(for: Data(normalized.utf8), using: SymmetricKey(data: salt))
        return Data(mac).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
