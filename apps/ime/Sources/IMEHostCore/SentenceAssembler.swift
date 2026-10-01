import Foundation

/// Joins commits into sentences, one buffer for the field being typed in. A sentence ends at
/// sentence punctuation or a newline, on `Return`, or when commits arrive from another field (a new
/// input session) or app. Leaving the field and coming back (to copy a link, say) does not end it;
/// only a very long pause does. Sentences live in memory only.
final class SentenceAssembler {
    struct Sentence: Equatable {
        let text: String
        let app: String
    }

    /// A message can take minutes to write; only an abandoned one is cut by time.
    static let pause: TimeInterval = 600
    static let recentLimit = 5
    static let enders: Set<Character> = ["。", "！", "？", "；", "!", "?", ";", "."]

    private var buffer = ""
    private var app: String?
    private var session: Int?
    private var lastCommit: Date?
    /// The last few sentences per app, oldest first, for suggestions that look back.
    private(set) var recent: [String: [String]] = [:]
    var onSentence: ((Sentence) -> Void)?

    /// The app of the unfinished sentence, if any text is buffered.
    var pendingApp: String? {
        buffer.isEmpty ? nil : app
    }

    /// `session` identifies the input field (the IMK input controller); a different one starts a new sentence.
    func commit(_ text: String, app: String, session: Int = 0, at date: Date) {
        if self.app != app || self.session != session || lastCommit.map({ date.timeIntervalSince($0) > Self.pause }) == true {
            endSentence()
        }
        self.app = app
        self.session = session
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
        remember(text, in: app)
        onSentence?(Sentence(text: text, app: app))
    }

    /// Records a sentence that came from elsewhere (a field read at `Return`) as recent.
    func remember(_ text: String, in app: String) {
        var sentences = recent[app, default: []]
        if sentences.last != text {
            sentences.append(text)
        }
        recent[app] = Array(sentences.suffix(Self.recentLimit))
    }

    func forgetRecent() {
        buffer = ""
        lastCommit = nil
        recent = [:]
    }
}
