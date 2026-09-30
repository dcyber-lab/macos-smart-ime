import Foundation
import Translation
import EnglishEngine
import UserData

struct TermTranslation: Equatable, Sendable {
    let english: String
    /// `english` translated back to Chinese.
    let roundTrip: String
}

protocol TermTranslator: Sendable {
    /// Nil when the Chinese and English translation languages are not installed; otherwise one result per
    /// word, nil where translating that word failed.
    func translate(_ words: [String]) async -> [TermTranslation?]?
}

/// Simplified Chinese -> English and back with Apple's on-device Translation framework.
struct AppleTermTranslator: TermTranslator {
    func translate(_ words: [String]) async -> [TermTranslation?]? {
        guard #available(macOS 26.0, *) else {
            return nil
        }
        let chinese = TranslationDirection.chineseToEnglish.source
        let english = TranslationDirection.chineseToEnglish.target
        let availability = LanguageAvailability()
        guard case .installed = await availability.status(from: chinese, to: english),
              case .installed = await availability.status(from: english, to: chinese) else {
            return nil
        }

        let forward = TranslationSession(installedSource: chinese, target: english)
        let backward = TranslationSession(installedSource: english, target: chinese)
        var results: [TermTranslation?] = []
        for word in words {
            do {
                let translated = try await forward.translate(word).targetText
                let roundTrip = try await backward.translate(translated).targetText
                results.append(TermTranslation(english: translated, roundTrip: roundTrip))
            } catch {
                results.append(nil)
            }
        }
        return results
    }
}

/// Learns English for Chinese words the user commits often but that have no translation: at most once per
/// interval, in the background, on-device. Kept translations go to the user's translation file.
@MainActor
final class TranslationLearner {
    struct Outcome: Equatable {
        var learned = 0
        var rejected = 0
        /// Words that gained a translation since they were counted.
        var skipped = 0
        var languagesMissing = false
    }

    static let minimumCommits = 3
    static let wordsPerRun = 50
    static let maxWords = 4
    static let maxLength = 40
    /// How soon to check again when the translation languages are not installed.
    static let missingLanguagesRetryDelay: TimeInterval = 60 * 60

    private let misses: TranslationMisses
    private let userTranslations: UserTranslations
    private let dictionary: ChineseEnglishDictionary
    private let lexicon: EnglishLexicon
    private let translator: TermTranslator
    private let settings: () -> TranslationLearningSettings
    private let clock: () -> Date
    private var isRunning = false
    private var nextLanguageCheck: Date?

    init(
        misses: TranslationMisses,
        userTranslations: UserTranslations,
        dictionary: ChineseEnglishDictionary = .bundled,
        lexicon: EnglishLexicon = .bundled,
        translator: TermTranslator = AppleTermTranslator(),
        settings: @escaping () -> TranslationLearningSettings = { TranslationLearningSettings() },
        clock: @escaping () -> Date = { Date() }
    ) {
        self.misses = misses
        self.userTranslations = userTranslations
        self.dictionary = dictionary
        self.lexicon = lexicon
        self.translator = translator
        self.settings = settings
        self.clock = clock
    }

    var isDue: Bool {
        let settings = settings()
        let now = clock()
        guard settings.isEnabled, !isRunning, nextLanguageCheck.map({ now >= $0 }) ?? true else {
            return false
        }
        if let lastRun = misses.lastRun, now.timeIntervalSince(lastRun) < settings.interval {
            return false
        }
        return !misses.candidates(minimumCount: Self.minimumCommits, limit: 1).isEmpty
    }

    /// Starts a run in the background when one is due. Cheap enough to call whenever an input controller activates.
    @discardableResult
    func runIfDue() -> Task<Outcome, Never>? {
        guard isDue else {
            return nil
        }
        isRunning = true
        return Task {
            let outcome = await run()
            isRunning = false
            return outcome
        }
    }

    func run() async -> Outcome {
        var outcome = Outcome()
        var words: [String] = []
        for candidate in misses.candidates(minimumCount: Self.minimumCommits, limit: Self.wordsPerRun) {
            if userTranslations.translations(for: candidate.text) != nil
                || !dictionary.translations(for: candidate.text).isEmpty {
                misses.forget(candidate.text)
                outcome.skipped += 1
            } else {
                words.append(candidate.text)
            }
        }
        guard !words.isEmpty else {
            misses.recordRun()
            return outcome
        }

        guard let results = await translator.translate(words) else {
            // Leave `lastRun` alone so installing the languages takes effect within the hour.
            nextLanguageCheck = clock().addingTimeInterval(Self.missingLanguagesRetryDelay)
            outcome.languagesMissing = true
            NSLog("SmartIME: translation learning skipped: Chinese and English translation languages not installed")
            return outcome
        }
        for (word, result) in zip(words, results) {
            // A failed word is tried again on the next run.
            guard let result else {
                continue
            }
            if let english = accepted(result, for: word) {
                userTranslations.addLearned(word, translations: [english])
                outcome.learned += 1
            } else {
                outcome.rejected += 1
            }
            misses.markProcessed(word)
        }
        misses.recordRun()
        NSLog("SmartIME: translation learning kept %d, rejected %d", outcome.learned, outcome.rejected)
        return outcome
    }

    /// The English to keep: 1–4 plain words whose translation back is the word itself, in lexicon casing.
    func accepted(_ translation: TermTranslation, for word: String) -> String? {
        var english = translation.english.trimmingCharacters(in: .whitespacesAndNewlines)
        if english.hasSuffix(".") {
            english.removeLast()
        }
        let words = english.split(separator: " ")
        guard (1...Self.maxWords).contains(words.count),
              english.count <= Self.maxLength,
              english.contains(where: \.isLetter),
              english.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || " -'".contains($0)) }),
              translation.roundTrip.filter({ !$0.isWhitespace && !"。.".contains($0) }) == word else {
            return nil
        }
        return lexiconCase(of: english)
    }

    /// "Kernel space" -> "kernel space" and "Github" -> "GitHub", but "Zhang Wei", "API gateway", and "ByteDance"
    /// stay as translated.
    private func lexiconCase(of english: String) -> String {
        let words = english.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let first = words.first, let display = lexicon.displayForm(of: first),
              EnglishLexicon.key(for: first) == first.lowercased() else {
            return english
        }
        if words.count == 1, display != display.lowercased() {
            return display
        }
        let isSentenceCase = first.first?.isUppercase == true
            && !first.dropFirst().contains(where: \.isUppercase)
            && !words.dropFirst().joined().contains(where: \.isUppercase)
        guard isSentenceCase, display == display.lowercased(), lexicon.isCommon(display) else {
            return english
        }
        return ([first.lowercased()] + words.dropFirst()).joined(separator: " ")
    }
}
