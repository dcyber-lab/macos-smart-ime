import Foundation
import SharedModels
import UserData

/// Wraps a Chinese engine and merges English word and translation candidates into its candidate list.
public final class EnglishAugmentedChineseEngine: ChineseInputEngine {
    private static let spaceKeyCode: UInt16 = 49
    private static let maxCandidates = 9
    private static let maxWordCandidates = 3
    private static let maxTranslations = 2
    private static let minimumInputLength = 3
    private static let minimumPromotionLength = 4
    private static let minimumRareWordLength = 5
    /// Picks beside the first Chinese candidate; more would push Chinese candidates off the page.
    private static let maxSecondPlace = 2
    /// An English pick displaces Chinese for pinyin input only after this many picks.
    private static let minimumPicksToLeadPinyin = 2

    private enum Entry {
        case chinese(pageIndex: Int)
        case english(Candidate)

        var isEnglish: Bool {
            if case .english = self {
                return true
            }
            return false
        }
    }

    private typealias EnglishOption = (text: String, source: CandidateSource)

    private enum Highlight {
        /// Index 0 when it is English, otherwise whatever the wrapped engine highlights.
        case automatic
        case chinese
        case english(Int)
    }

    private let base: ChineseInputEngine
    private let lexicon: EnglishLexicon
    private let dictionary: ChineseEnglishDictionary
    private let glossary: EnglishGlossary
    private let history: CandidateHistory?
    private var baseState = CompositionState()
    private var entries: [Entry] = []
    private var highlight = Highlight.automatic

    public init(
        base: ChineseInputEngine,
        lexicon: EnglishLexicon = .bundled,
        dictionary: ChineseEnglishDictionary = .bundled,
        glossary: EnglishGlossary = .bundled,
        history: CandidateHistory? = nil
    ) {
        self.base = base
        self.lexicon = lexicon
        self.dictionary = dictionary
        self.glossary = glossary
        self.history = history
    }

    public func process(_ event: InputKeyEvent) -> InputSessionUpdate {
        if event.keyCode == Self.spaceKeyCode, let candidate = highlightedEnglishCandidate {
            return commit(candidate)
        }

        highlight = .automatic
        let update = base.process(event)
        if event.keyCode == Self.spaceKeyCode, update.commitText != nil {
            recordChinesePick()
        }
        return merge(update)
    }

    public func selectCandidate(at index: Int) -> InputSessionUpdate {
        switch entry(at: index) {
        case .english(let candidate):
            return commit(candidate)
        case .chinese(let pageIndex):
            highlight = .automatic
            let update = base.selectCandidate(at: pageIndex)
            if update.commitText != nil {
                recordChinesePick()
            }
            return merge(update)
        case nil:
            return merge(base.selectCandidate(at: index))
        }
    }

    public func highlightCandidate(at index: Int) -> InputSessionUpdate {
        switch entry(at: index) {
        case .english:
            highlight = .english(index)
            return InputSessionUpdate(handled: true, state: mergedState())
        case .chinese(let pageIndex):
            highlight = .chinese
            return merge(base.highlightCandidate(at: pageIndex))
        case nil:
            return merge(base.highlightCandidate(at: index))
        }
    }

    public func reset() {
        base.reset()
        baseState = CompositionState()
        entries = []
        highlight = .automatic
    }

    private var highlightedEnglishCandidate: Candidate? {
        let index: Int
        switch highlight {
        case .automatic:
            index = 0
        case .english(let englishIndex):
            index = englishIndex
        case .chinese:
            return nil
        }

        if case .english(let candidate) = entry(at: index) {
            return candidate
        }
        return nil
    }

    private func entry(at index: Int) -> Entry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    private func commit(_ candidate: Candidate) -> InputSessionUpdate {
        let mode = baseState.mode
        history?.recordChoice(input: baseState.rawInput, english: candidate.text)
        history?.recordWord(candidate.text, in: lexicon)
        reset()
        return InputSessionUpdate(
            handled: true,
            state: CompositionState(mode: mode, recentText: candidate.text),
            commitText: candidate.text
        )
    }

    private func merge(_ update: InputSessionUpdate) -> InputSessionUpdate {
        baseState = update.state
        entries = makeEntries()
        return InputSessionUpdate(handled: update.handled, state: mergedState(), commitText: update.commitText)
    }

    private func mergedState() -> CompositionState {
        var state = baseState
        if showsRawInputAsPreedit {
            state.compositionText = baseState.rawInput
        }
        state.candidates = entries.map { entry in
            switch entry {
            case .chinese(let pageIndex):
                return baseState.candidates[pageIndex]
            case .english(let candidate):
                return candidate
            }
        }
        state.selectedCandidateIndex = mergedSelectedIndex()
        return state
    }

    private func mergedSelectedIndex() -> Int? {
        switch highlight {
        case .english(let index):
            return index
        case .automatic where highlightedEnglishCandidate != nil:
            return 0
        case .automatic, .chinese:
            guard let baseIndex = baseState.selectedCandidateIndex else {
                return nil
            }
            let mergedIndex = entries.firstIndex {
                if case .chinese(let pageIndex) = $0 {
                    return pageIndex == baseIndex
                }
                return false
            }
            return mergedIndex ?? baseIndex
        }
    }

    private func makeEntries() -> [Entry] {
        let chinese = baseState.candidates.indices.map { Entry.chinese(pageIndex: $0) }
        let input = baseState.rawInput
        guard isEligible(input) else {
            return chinese
        }

        let isPinyin = PinyinSyllableSegmenter.canSegment(input)
        // The long tail is full of abbreviations and romanized names ("dep", "shuji") that collide with pinyin.
        let allowsRareWords = !isPinyin && input.count >= Self.minimumRareWordLength
        let isUsable = { (word: String) in allowsRareWords || self.lexicon.isCommon(word) }
        let exactWord = lexicon.displayForm(of: input).flatMap { isUsable($0) ? $0 : nil }
        let completions = lexicon
            .completions(forPrefix: input, limit: Self.maxWordCandidates + 1, preferring: history)
            .filter { $0 != exactWord && isUsable($0) }
        let words = Array(((exactWord.map { [$0] } ?? []) + completions).prefix(Self.maxWordCandidates))
        let translations = translationsOfFirstCandidate()
        let choices = history?.choices(for: input) ?? .empty

        // English candidates the user picked for this input before and that still fit it, most picked first.
        let picks = choices.english.compactMap { pick -> (pick: CandidateHistory.Pick, option: EnglishOption)? in
            if translations.contains(pick.text) {
                return (pick, (pick.text, .englishTranslation))
            }
            let completesInput = EnglishLexicon.key(for: pick.text).hasPrefix(input)
            return completesInput && lexicon.displayForm(of: pick.text) == pick.text && isUsable(pick.text)
                ? (pick, (pick.text, .englishCompletion))
                : nil
        }
        // A pick leads once it beats Chinese for this input; pinyin input also needs repeated picks.
        let leadingPick = picks.first.flatMap { top in
            top.pick.score > choices.chinese && (!isPinyin || top.pick.count >= Self.minimumPicksToLeadPinyin)
                ? top.option
                : nil
        }
        // A finished common English word that is not pinyin goes first so Space commits it,
        // unless the user picks Chinese for this input more often.
        let leadingWord = !isPinyin ? exactWord.flatMap { lexicon.isCommon($0) ? $0 : nil } : nil
        let wordLeads = leadingWord.map { choices.chinese <= choices.score(of: $0) } ?? false
        let first = leadingPick ?? (wordLeads ? leadingWord.map { ($0, .englishCompletion) } : nil)

        // Longer non-pinyin input gets its best completion right after the first Chinese candidate,
        // reachable with number key 2 while Space still commits Chinese.
        let promoted = !wordLeads && !isPinyin && input.count >= Self.minimumPromotionLength
            ? completions.first(where: lexicon.isCommon)
            : nil
        let secondPlace: [EnglishOption] = picks.map(\.option)
            + [leadingWord, promoted].compactMap { $0.map { ($0, .englishCompletion) } }
        // Translations of a non-pinyin English word's Chinese candidates would be noise.
        let trailing: [EnglishOption] = (wordLeads ? [] : translations.prefix(Self.maxTranslations))
            .map { ($0, .englishTranslation) }
            + words.map { ($0, .englishCompletion) }

        var seen = Set(baseState.candidates.map(\.text))
        func english(_ option: EnglishOption) -> Entry? {
            guard seen.insert(option.text).inserted else {
                return nil
            }
            // Translations need no gloss: the user just typed the Chinese.
            let annotation = option.source == .englishCompletion ? glossary.gloss(for: option.text) : nil
            return .english(Candidate(text: option.text, source: option.source, annotation: annotation))
        }

        let leading = [first].compactMap { $0.flatMap(english) }
        // Stop at the limit so options left out here can still appear after the Chinese candidates.
        var second: [Entry] = []
        for option in secondPlace where second.count < Self.maxSecondPlace {
            english(option).map { second.append($0) }
        }
        let merged = leading
            + chinese.prefix(1)
            + second
            + chinese.dropFirst()
            + trailing.compactMap(english)
        return Array(merged.prefix(Self.maxCandidates))
    }

    /// Records a Space or number-key pick of Chinese, only for inputs where English came first or was picked
    /// before, so English stops leading once the user prefers Chinese. Other Chinese typing is librime's to learn.
    /// Call before `merge` replaces the state being picked from.
    private func recordChinesePick() {
        let input = baseState.rawInput
        guard let history, isLearnable(input) else {
            return
        }
        if entries.first?.isEnglish == true || !history.choices(for: input).english.isEmpty {
            history.recordChoice(input: input, english: nil)
        }
    }

    /// librime shows non-pinyin input as syllable fragments ("good" -> "go o d"); show what was typed instead,
    /// unless part of it has already been converted to Chinese.
    private var showsRawInputAsPreedit: Bool {
        let input = baseState.rawInput
        return baseState.mode == .chinese
            && !input.isEmpty
            && input.allSatisfy { $0.isASCII && $0.isLowercase }
            && baseState.compositionText.allSatisfy(\.isASCII)
            && !PinyinSyllableSegmenter.canSegment(input)
    }

    private func isEligible(_ input: String) -> Bool {
        baseState.mode == .chinese && baseState.candidatePageIndex == 0 && isLearnable(input)
    }

    private func isLearnable(_ input: String) -> Bool {
        input.count >= Self.minimumInputLength && input.allSatisfy { $0.isASCII && $0.isLowercase }
    }

    private func translationsOfFirstCandidate() -> [String] {
        guard let first = baseState.candidates.first?.text, first.count >= 2 else {
            return []
        }
        return dictionary.translations(for: first)
    }
}
