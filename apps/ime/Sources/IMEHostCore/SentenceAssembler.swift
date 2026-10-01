import Foundation

/// Joins commits into sentences, one buffer at a time for the app being typed in. A sentence ends
/// at sentence punctuation or a newline, after a pause, on `Return`, on a switch to another app,
/// or when the input method is deactivated. Sentences live in memory only.
final class SentenceAssembler {
    struct Sentence: Equatable {
        let text: String
        let app: String
    }

    static let pause: TimeInterval = 10
    static let recentLimit = 5
    private static let enders: Set<Character> = ["。", "！", "？", "；", "!", "?", ";", "."]

    private var buffer = ""
    private var app: String?
    private var lastCommit: Date?
    /// The last few sentences per app, oldest first, for suggestions that look back.
    private(set) var recent: [String: [String]] = [:]
    var onSentence: ((Sentence) -> Void)?

    func commit(_ text: String, app: String, at date: Date) {
        if self.app != app || lastCommit.map({ date.timeIntervalSince($0) > Self.pause }) == true {
            endSentence()
        }
        self.app = app
        lastCommit = date
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if index > 0 {
                endSentence()
            }
            buffer += line
        }
        if let last = buffer.trimmingCharacters(in: .whitespaces).last, Self.enders.contains(last) {
            endSentence()
        }
    }

    func endSentence() {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        lastCommit = nil
        guard let app, !text.isEmpty else {
            return
        }
        var sentences = recent[app, default: []]
        sentences.append(text)
        recent[app] = Array(sentences.suffix(Self.recentLimit))
        onSentence?(Sentence(text: text, app: app))
    }

    func forgetRecent() {
        buffer = ""
        lastCommit = nil
        recent = [:]
    }
}
