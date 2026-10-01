import Foundation
import UserData

/// Feeds committed text into the input memory and journal, under the privacy rules: nothing while
/// learning is off, in excluded apps, or under secure input; sensitive sentences are dropped whole.
/// Called on commit only, never per keystroke.
///
/// When a sentence ends while the client is still focused (punctuation, `Return`), the journal entry
/// also gets the text just before it in the same field. That read is a round trip to the client app,
/// so it runs after the key has been handled, is timed, and stops for an app once a read is slow.
@MainActor
final class IntelligenceRecorder {
    /// Per-app outcome of reading the text before the cursor, for the learning page.
    struct ContextStats: Equatable {
        var reads = 0
        var found = 0
        var totalSeconds = 0.0
        var slowestSeconds = 0.0
        /// Set after a read slower than `slowRead`; the app is not read again in this session.
        var isStopped = false

        var averageMilliseconds: Double { reads > 0 ? totalSeconds / Double(reads) * 1000 : 0 }
    }

    nonisolated static let slowRead: TimeInterval = 0.1
    nonisolated static let contextLimit = 300

    let settings: IntelligenceSettings
    let memory: InputMemory
    let journal: InputJournal
    private(set) var contextStats: [String: ContextStats] = [:]
    private let assembler = SentenceAssembler()
    private let clock: () -> Date
    private let later: (@escaping @MainActor () -> Void) -> Void
    /// Set for the duration of a commit that can read the client.
    private var readContext: (() -> String?)?

    /// `later` runs work after the current key has been handled; tests pass `{ $0() }`.
    init(
        settings: IntelligenceSettings, memory: InputMemory, journal: InputJournal,
        clock: @escaping () -> Date = { Date() },
        later: @escaping (@escaping @MainActor () -> Void) -> Void = { work in Task { @MainActor in work() } }
    ) {
        self.settings = settings
        self.memory = memory
        self.journal = journal
        self.clock = clock
        self.later = later
        assembler.onSentence = { [weak self] sentence in
            self?.learn(sentence)
        }
    }

    /// `readContext` returns the text before the cursor in the client; it is only called when this
    /// commit ends a sentence that goes to the journal.
    func commit(_ text: String, app: String?, secureInput: Bool, readContext: (() -> String?)? = nil) {
        guard settings.isLearningEnabled, !secureInput, let app, settings.allows(app: app) else {
            // Leaving an allowed app still closes what was typed there.
            assembler.endSentence()
            return
        }
        self.readContext = readContext
        defer { self.readContext = nil }
        assembler.commit(text, app: app, at: clock())
    }

    /// `Return` without a composition (pass `readContext`), or the input method losing focus (do not).
    func endSentence(readContext: (() -> String?)? = nil) {
        self.readContext = readContext
        defer { self.readContext = nil }
        assembler.endSentence()
    }

    func recentSentences(in app: String) -> [String] {
        assembler.recent[app] ?? []
    }

    /// Deletes everything learned, on disk and in memory.
    func clear() {
        assembler.forgetRecent()
        memory.clear()
        journal.clear()
        contextStats = [:]
    }

    private func learn(_ sentence: SentenceAssembler.Sentence) {
        guard PrivacyFilter.allowsSentence(sentence.text) else {
            return
        }
        memory.record(sentence: sentence.text, app: sentence.app)
        guard settings.isJournalEnabled else {
            return
        }
        guard let read = readContext, contextStats[sentence.app]?.isStopped != true else {
            journal.append(sentence.text, app: sentence.app)
            return
        }
        later { [weak self] in
            guard let self else { return }
            let start = Date()
            let before = read()
            let seconds = Date().timeIntervalSince(start)
            let context = Self.context(before: sentence.text, in: before)
            var stats = contextStats[sentence.app] ?? ContextStats()
            stats.reads += 1
            stats.found += context == nil ? 0 : 1
            stats.totalSeconds += seconds
            stats.slowestSeconds = max(stats.slowestSeconds, seconds)
            stats.isStopped = stats.isStopped || seconds > Self.slowRead
            contextStats[sentence.app] = stats
            journal.append(sentence.text, app: sentence.app, context: context)
        }
    }

    /// The text before `sentence` in what the client reported: the sentence itself and surrounding
    /// whitespace removed, the last `contextLimit` characters kept, dropped if it looks sensitive.
    nonisolated static func context(before sentence: String, in reported: String?) -> String? {
        guard var text = reported?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let range = text.range(of: sentence, options: .backwards) {
            text = String(text[..<range.lowerBound])
        }
        text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(contextLimit))
        guard !text.isEmpty, PrivacyFilter.allowsSentence(text) else {
            return nil
        }
        return text
    }
}
