import Foundation
import UserData

/// Feeds committed text into the input memory and journal, under the privacy rules: nothing while
/// learning is off, in excluded apps, or under secure input; sensitive spans (links, emails, codes,
/// tokens) are masked. Called on commit and on `Return` only, never per keystroke.
///
/// The input method only sees text it commits itself, not pasted links, picked @mentions, or digits
/// the app inserts directly. So when a sentence ends while its field is focused, the recorder reads
/// the field and journals the sentence as the field has it, with the text before it as context:
/// - on `Return`, before the key reaches the app (a chat app sends and clears the field on `Return`);
/// - on sentence punctuation, after the key has been handled.
/// Each read is a round trip to the client app: it is timed per app and stops for an app once a read
/// is slow. The focused window's title is read the same deferred way when enabled.
@MainActor
final class IntelligenceRecorder {
    /// Per-app outcome of reading the field or the window title, for the learning page.
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
    nonisolated static let sentenceLimit = 1_000
    nonisolated static let windowTitleLimit = 120

    let settings: IntelligenceSettings
    let memory: InputMemory
    let journal: InputJournal
    private(set) var contextStats: [String: ContextStats] = [:]
    private(set) var windowStats: [String: ContextStats] = [:]
    private let assembler = SentenceAssembler()
    private let clock: () -> Date
    private let later: (@escaping @MainActor () -> Void) -> Void

    /// How the sentence being closed ended, set around calls into the assembler.
    private enum Ending {
        case quiet
        case punctuation(readField: (() -> String?)?)
        /// The field as read just before `Return` reached the app.
        case returnKey(field: String?)
    }

    private var ending = Ending.quiet
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

    /// `readField` returns the text before the cursor in the client and `readWindowTitle` the focused
    /// window's title; they are only called, after the key, when this commit ends a sentence.
    /// `session` identifies the input field (the IMK input controller).
    func commit(
        _ text: String, app: String?, session: Int = 0, secureInput: Bool,
        readField: (() -> String?)? = nil, readWindowTitle: (() -> String?)? = nil
    ) {
        guard isRecording(app: app, secureInput: secureInput), let app else {
            // Typing elsewhere still closes what was typed in an allowed app.
            closeQuietly()
            return
        }
        ending = .punctuation(readField: readField)
        self.readWindowTitle = readWindowTitle
        defer { (ending, self.readWindowTitle) = (.quiet, nil) }
        assembler.commit(text, app: app, session: session, at: clock())
    }

    /// `Return` without a composition. Reads the field now, before the app handles the key, and journals
    /// the line it ends, even when the input method committed none of it (a pasted link, say).
    func endLine(
        app: String?, secureInput: Bool, readField: (() -> String?)? = nil, readWindowTitle: (() -> String?)? = nil
    ) {
        guard isRecording(app: app, secureInput: secureInput), let app else {
            closeQuietly()
            return
        }
        var field: String?
        if settings.isJournalEnabled, let readField, contextStats[app]?.isStopped != true {
            field = Self.timed(readField, into: &contextStats[app, default: ContextStats()]) { $0 }
        }
        ending = .returnKey(field: field)
        self.readWindowTitle = readWindowTitle
        defer { (ending, self.readWindowTitle) = (.quiet, nil) }
        let hadText = assembler.pendingApp == app
        assembler.endSentence()
        if !hadText, let field, Self.line(endingAt: field) != nil {
            learn(.init(text: "", app: app))
        }
    }

    /// Ends the open sentence without reading anything (learning turned off, app excluded).
    func closeQuietly() {
        ending = .quiet
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

    private func isRecording(app: String?, secureInput: Bool) -> Bool {
        settings.isLearningEnabled && !secureInput && settings.allows(app: app)
    }

    private func learn(_ sentence: SentenceAssembler.Sentence) {
        let app = sentence.app
        guard settings.isJournalEnabled else {
            record(sentence.text, app: app, context: nil, window: nil)
            return
        }
        let readTitle = windowStats[app]?.isStopped == true ? nil : readWindowTitle
        switch ending {
        case .quiet:
            record(sentence.text, app: app, context: nil, window: nil)
        case .returnKey(let field):
            let fromField = field.flatMap { Self.line(endingAt: $0) }.flatMap { Self.consistent($0, with: sentence.text) }
            later { [weak self] in
                guard let self else { return }
                record(fromField?.text ?? sentence.text, app: app, context: fromField?.context, window: title(readTitle, app: app))
            }
        case .punctuation(let readField):
            let readField = contextStats[app]?.isStopped == true ? nil : readField
            later { [weak self] in
                guard let self else { return }
                let field = readField.flatMap { read in Self.timed(read, into: &contextStats[app, default: ContextStats()]) { $0 } }
                let fromField = field.flatMap { Self.sentence(endingAt: $0) }.flatMap { Self.consistent($0, with: sentence.text) }
                record(fromField?.text ?? sentence.text, app: app, context: fromField?.context, window: title(readTitle, app: app))
            }
        }
    }

    private func title(_ read: (() -> String?)?, app: String) -> String? {
        read.flatMap { read in Self.timed(read, into: &windowStats[app, default: ContextStats()]) { Self.windowTitle($0) } }
    }

    /// Masks, then learns: statistics always, the journal when it is on.
    private func record(_ text: String, app: String, context: String?, window: String?) {
        let text = String(PrivacyFilter.redact(text).prefix(Self.sentenceLimit))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        memory.record(sentence: text, app: app)
        assembler.remember(text, in: app)
        if settings.isJournalEnabled {
            journal.append(text, app: app, context: context.map(PrivacyFilter.redact), window: window)
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
        stats.found += (value?.isEmpty ?? true) ? 0 : 1
        stats.totalSeconds += seconds
        stats.slowestSeconds = max(stats.slowestSeconds, seconds)
        stats.isStopped = stats.isStopped || seconds > slowRead
        return value
    }

    // MARK: Reading the field

    struct FieldSentence: Equatable {
        let text: String
        let context: String?
    }

    /// The line the cursor ends (`Return`): the text after the last newline, and up to `contextLimit`
    /// characters of what comes before it.
    nonisolated static func line(endingAt field: String) -> FieldSentence? {
        let trimmed = String(field.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        let start = trimmed.lastIndex(of: "\n").map { trimmed.index(after: $0) } ?? trimmed.startIndex
        return split(trimmed, at: start)
    }

    /// The sentence that just ended with punctuation: from the previous sentence end or newline to the
    /// end of the field, and up to `contextLimit` characters before it.
    nonisolated static func sentence(endingAt field: String) -> FieldSentence? {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.indices.last else {
            return nil
        }
        var start = trimmed.startIndex
        var index = last
        while index > trimmed.startIndex {
            index = trimmed.index(before: index)
            if isBoundary(at: index, in: trimmed) {
                start = trimmed.index(after: index)
                break
            }
        }
        return split(trimmed, at: start)
    }

    /// A newline, CJK or !?; punctuation, or a period followed by whitespace ("v2.3" and "e.g" do not end a sentence).
    private nonisolated static func isBoundary(at index: String.Index, in text: String) -> Bool {
        let character = text[index]
        if character == "\n" {
            return true
        }
        guard SentenceAssembler.enders.contains(character) else {
            return false
        }
        guard character == "." else {
            return true
        }
        let next = text.index(after: index)
        return next == text.endIndex || text[next].isWhitespace
    }

    private nonisolated static func split(_ text: String, at start: String.Index) -> FieldSentence? {
        let sentence = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else {
            return nil
        }
        let before = String(text[..<start].trimmingCharacters(in: .whitespacesAndNewlines).suffix(contextLimit))
        return FieldSentence(text: String(sentence.prefix(sentenceLimit)), context: before.isEmpty ? nil : before)
    }

    /// The field's sentence, if it is the one the user typed: the last characters the input method
    /// committed must appear in it in order (spaces ignored; text the app inserted directly, like digits
    /// or a pasted link, may sit between them). An empty commit (only pasted text) accepts the field.
    nonisolated static func consistent(_ field: FieldSentence, with assembled: String) -> FieldSentence? {
        let tail = Array(assembled.filter { !$0.isWhitespace }.suffix(8))
        guard !tail.isEmpty else {
            return field
        }
        var remaining = tail[...]
        for character in field.text where !character.isWhitespace {
            if character == remaining.first {
                remaining = remaining.dropFirst()
                if remaining.isEmpty {
                    return field
                }
            }
        }
        return nil
    }

    /// A window title kept for the journal: trimmed, masked, at most `windowTitleLimit` characters.
    nonisolated static func windowTitle(_ reported: String?) -> String? {
        guard let title = reported?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return String(PrivacyFilter.redact(title).prefix(windowTitleLimit))
    }
}
