import Foundation
import UserData

/// Feeds committed text into the input memory and journal, under the privacy rules: nothing while
/// learning is off, in excluded apps, or under secure input; sensitive sentences are dropped whole.
/// Called on commit only, never per keystroke.
///
/// When a sentence ends while the client is still focused (punctuation, `Return`), the journal entry
/// also gets the text just before it in the same field and, when enabled, the focused window's title.
/// Each read is a round trip to the client app, so it runs after the key has been handled, is timed,
/// and stops for an app once a read is slow.
@MainActor
final class IntelligenceRecorder {
    /// Per-app outcome of reading the text before the cursor or the window title, for the learning page.
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
    nonisolated static let windowTitleLimit = 120

    let settings: IntelligenceSettings
    let memory: InputMemory
    let journal: InputJournal
    private(set) var contextStats: [String: ContextStats] = [:]
    private(set) var windowStats: [String: ContextStats] = [:]
    private let assembler = SentenceAssembler()
    private let clock: () -> Date
    private let later: (@escaping @MainActor () -> Void) -> Void
    /// Set for the duration of a commit that can read the client.
    private var readContext: (() -> String?)?
    private var readWindowTitle: (() -> String?)?

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

    /// `readContext` returns the text before the cursor in the client and `readWindowTitle` the focused
    /// window's title; they are only called when this commit ends a sentence that goes to the journal.
    func commit(
        _ text: String, app: String?, secureInput: Bool,
        readContext: (() -> String?)? = nil, readWindowTitle: (() -> String?)? = nil
    ) {
        guard settings.isLearningEnabled, !secureInput, let app, settings.allows(app: app) else {
            // Leaving an allowed app still closes what was typed there.
            assembler.endSentence()
            return
        }
        self.readContext = readContext
        self.readWindowTitle = readWindowTitle
        defer { (self.readContext, self.readWindowTitle) = (nil, nil) }
        assembler.commit(text, app: app, at: clock())
    }

    /// `Return` without a composition (pass `readContext`), or the input method losing focus (do not).
    func endSentence(readContext: (() -> String?)? = nil, readWindowTitle: (() -> String?)? = nil) {
        self.readContext = readContext
        self.readWindowTitle = readWindowTitle
        defer { (self.readContext, self.readWindowTitle) = (nil, nil) }
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
        windowStats = [:]
    }

    private func learn(_ sentence: SentenceAssembler.Sentence) {
        guard PrivacyFilter.allowsSentence(sentence.text) else {
            return
        }
        memory.record(sentence: sentence.text, app: sentence.app)
        guard settings.isJournalEnabled else {
            return
        }
        let app = sentence.app
        let readText = contextStats[app]?.isStopped == true ? nil : self.readContext
        let readTitle = windowStats[app]?.isStopped == true ? nil : self.readWindowTitle
        guard readText != nil || readTitle != nil else {
            journal.append(sentence.text, app: app)
            return
        }
        later { [weak self] in
            guard let self else { return }
            let context = readText.flatMap { read in
                Self.timed(read, into: &contextStats[app, default: ContextStats()]) { Self.context(before: sentence.text, in: $0) }
            }
            let window = readTitle.flatMap { read in
                Self.timed(read, into: &windowStats[app, default: ContextStats()]) { Self.windowTitle($0) }
            }
            journal.append(sentence.text, app: app, context: context, window: window)
        }
    }

    /// Runs one read, cleans its result, and records how it went. Only the read (the round trip to the
    /// app) is timed; cleaning runs locally and must not make an app look slow.
    private static func timed(_ read: () -> String?, into stats: inout ContextStats, clean: (String?) -> String?) -> String? {
        let start = Date()
        let reported = read()
        let seconds = Date().timeIntervalSince(start)
        let value = clean(reported)
        stats.reads += 1
        stats.found += value == nil ? 0 : 1
        stats.totalSeconds += seconds
        stats.slowestSeconds = max(stats.slowestSeconds, seconds)
        stats.isStopped = stats.isStopped || seconds > slowRead
        return value
    }

    /// A window title kept for the journal: trimmed, at most `windowTitleLimit` characters, dropped if
    /// empty or if it looks sensitive (an email in a mail window, a URL, a code).
    nonisolated static func windowTitle(_ reported: String?) -> String? {
        guard let title = reported?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              PrivacyFilter.allowsSentence(title) else {
            return nil
        }
        return String(title.prefix(windowTitleLimit))
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
