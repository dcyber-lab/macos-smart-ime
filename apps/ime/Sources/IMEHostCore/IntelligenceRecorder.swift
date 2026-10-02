import Foundation
import UserData

/// Text read from before the cursor in the client's field. `startsMidway` is set when the app
/// returned less than the whole field before the cursor (Chromium and Electron apps report only about
/// 100 characters around it).
struct FieldText: Equatable, Sendable {
    let text: String
    let startsMidway: Bool
    /// The cursor's location (UTF-16) in the client when it was read.
    let cursor: Int?

    init(_ text: String, startsMidway: Bool = false, cursor: Int? = nil) {
        self.text = text
        self.startsMidway = startsMidway
        self.cursor = cursor
    }

    /// Where `tail` sits in the client (UTF-16) when the text, without trailing whitespace, ends with it;
    /// nil when it does not (a sentence cut to a length limit) or the cursor is unknown.
    func range(ofTail tail: String) -> NSRange? {
        guard let cursor, !tail.isEmpty else {
            return nil
        }
        let body = text[..<(text.lastIndex { !$0.isWhitespace }.map(text.index(after:)) ?? text.startIndex)]
        guard body.hasSuffix(tail) else {
            return nil
        }
        let end = cursor - text[body.endIndex...].utf16.count
        let length = tail.utf16.count
        return NSRange(location: end - length, length: length)
    }
}

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
        case punctuation(readField: (() -> FieldText?)?)
        /// The field as read just before `Return` reached the app.
        case returnKey(field: FieldText?)
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
        readField: (() -> FieldText?)? = nil, readWindowTitle: (() -> String?)? = nil
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
        app: String?, secureInput: Bool, readField: (() -> FieldText?)? = nil, readWindowTitle: (() -> String?)? = nil
    ) {
        guard isRecording(app: app, secureInput: secureInput), let app else {
            closeQuietly()
            return
        }
        var field: FieldText?
        if settings.isJournalEnabled, let readField, contextStats[app]?.isStopped != true {
            field = Self.timed(readField, into: &contextStats[app, default: ContextStats()]) { !$0.text.isEmpty }
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
                record(Self.text(fromField, assembled: sentence.text), app: app, context: fromField?.context, window: title(readTitle, app: app))
            }
        case .punctuation(let readField):
            let readField = contextStats[app]?.isStopped == true ? nil : readField
            later { [weak self] in
                guard let self else { return }
                let field = readField.flatMap { read in Self.timed(read, into: &contextStats[app, default: ContextStats()]) { !$0.text.isEmpty } }
                let fromField = field.flatMap { Self.sentence(endingAt: $0) }.flatMap { Self.consistent($0, with: sentence.text) }
                record(Self.text(fromField, assembled: sentence.text), app: app, context: fromField?.context, window: title(readTitle, app: app))
            }
        }
    }

    private func title(_ read: (() -> String?)?, app: String) -> String? {
        read.flatMap { read in Self.windowTitle(Self.timed(read, into: &windowStats[app, default: ContextStats()]) { !$0.isEmpty }) }
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

    /// Runs one read and records how it went. Only the read (the round trip to the app) is timed.
    private static func timed<T>(_ read: () -> T?, into stats: inout ContextStats, isFound: (T) -> Bool) -> T? {
        let start = Date()
        let value = read()
        let seconds = Date().timeIntervalSince(start)
        stats.reads += 1
        stats.found += value.map(isFound) == true ? 1 : 0
        stats.totalSeconds += seconds
        stats.slowestSeconds = max(stats.slowestSeconds, seconds)
        stats.isStopped = stats.isStopped || seconds > slowRead
        return value
    }

    // MARK: Reading the field

    struct FieldSentence: Equatable {
        let text: String
        let context: String?
        /// The sentence starts where the app's text did, so earlier parts of it may be missing.
        var startsMidway = false
    }

    /// The sentence to journal: the field's when it matched, completed with what the input method
    /// committed before the app's window when the app reported only the end of a long sentence.
    nonisolated static func text(_ field: FieldSentence?, assembled: String) -> String {
        guard let field else {
            return assembled
        }
        return field.startsMidway ? merged(field.text, after: assembled) : field.text
    }

    /// `windowText` is the end of a sentence; `assembled` is everything the input method committed for
    /// it. Committed characters found in the window (matched from the end) are dropped from `assembled`;
    /// the rest came before the window and is put in front, with "…" where text may be missing.
    nonisolated static func merged(_ windowText: String, after assembled: String) -> String {
        let committed = Array(assembled)
        let window = Array(windowText)
        var i = committed.count - 1, j = window.count - 1
        while i >= 0, j >= 0 {
            if committed[i].isWhitespace {
                i -= 1
            } else {
                if committed[i] == window[j] {
                    i -= 1
                }
                j -= 1
            }
        }
        let head = i >= 0 ? String(committed[...i]).trimmingCharacters(in: .whitespaces) : ""
        return head.isEmpty ? "…" + windowText : head + " … " + windowText
    }

    /// The line the cursor ends (`Return`): the text after the last newline, and up to `contextLimit`
    /// characters of what comes before it.
    nonisolated static func line(endingAt field: FieldText) -> FieldSentence? {
        let trimmed = String(field.text.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        let start = trimmed.lastIndex(of: "\n").map { trimmed.index(after: $0) } ?? trimmed.startIndex
        return split(trimmed, at: start, startsMidway: field.startsMidway)
    }

    /// The sentence that just ended with punctuation: from the previous sentence end or newline to the
    /// end of the field, and up to `contextLimit` characters before it.
    nonisolated static func sentence(endingAt field: FieldText) -> FieldSentence? {
        let trimmed = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return split(trimmed, at: start, startsMidway: field.startsMidway)
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

    private nonisolated static func split(_ text: String, at start: String.Index, startsMidway: Bool) -> FieldSentence? {
        let sentence = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else {
            return nil
        }
        let before = String(text[..<start].trimmingCharacters(in: .whitespacesAndNewlines).suffix(contextLimit))
        return FieldSentence(text: String(sentence.prefix(sentenceLimit)), context: before.isEmpty ? nil : before,
                             startsMidway: startsMidway && start == text.startIndex)
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
