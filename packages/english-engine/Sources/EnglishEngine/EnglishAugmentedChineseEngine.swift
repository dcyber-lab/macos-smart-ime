import Foundation
import SharedModels

/// Wraps a Chinese engine and merges English word and translation candidates into its candidate list.
public final class EnglishAugmentedChineseEngine: ChineseInputEngine {
    private static let spaceKeyCode: UInt16 = 49
    private static let maxCandidates = 9
    private static let maxWordCandidates = 3
    private static let maxTranslations = 2
    private static let minimumInputLength = 3
    private static let minimumPromotionLength = 4
    private static let minimumRareWordLength = 5

    private enum Entry {
        case chinese(pageIndex: Int)
        case english(Candidate)
    }

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
    private var baseState = CompositionState()
    private var entries: [Entry] = []
    private var highlight = Highlight.automatic

    public init(
        base: ChineseInputEngine,
        lexicon: EnglishLexicon = .bundled,
        dictionary: ChineseEnglishDictionary = .bundled,
        glossary: EnglishGlossary = .bundled
    ) {
        self.base = base
        self.lexicon = lexicon
        self.dictionary = dictionary
        self.glossary = glossary
    }

    public func process(_ event: InputKeyEvent) -> InputSessionUpdate {
        if event.keyCode == Self.spaceKeyCode, let candidate = highlightedEnglishCandidate {
            return commit(candidate)
        }

        highlight = .automatic
        return merge(base.process(event))
    }

    public func selectCandidate(at index: Int) -> InputSessionUpdate {
        switch entry(at: index) {
        case .english(let candidate):
            return commit(candidate)
        case .chinese(let pageIndex):
            highlight = .automatic
            return merge(base.selectCandidate(at: pageIndex))
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
            .completions(forPrefix: input, limit: Self.maxWordCandidates + 1)
            .filter { $0 != exactWord && isUsable($0) }
        let words = Array(((exactWord.map { [$0] } ?? []) + completions).prefix(Self.maxWordCandidates))

        // A finished common English word that is not pinyin goes first so Space commits it.
        let leading = !isPinyin ? exactWord.flatMap { lexicon.isCommon($0) ? [$0] : nil } ?? [] : []
        // Longer non-pinyin input gets its best completion right after the first Chinese candidate,
        // reachable with number key 2 while Space still commits Chinese.
        let promoted = leading.isEmpty && !isPinyin && input.count >= Self.minimumPromotionLength
            ? Array(completions.filter(lexicon.isCommon).prefix(1))
            : []
        let translations = leading.isEmpty ? translationsOfFirstCandidate() : []
        let trailing = translations.map { ($0, CandidateSource.englishTranslation) }
            + words.filter { !leading.contains($0) && !promoted.contains($0) }.map { ($0, CandidateSource.englishCompletion) }

        var seen = Set(baseState.candidates.map(\.text))
        func english(_ text: String, _ source: CandidateSource) -> Entry? {
            guard seen.insert(text).inserted else {
                return nil
            }
            // Translations need no gloss: the user just typed the Chinese.
            let annotation = source == .englishCompletion ? glossary.gloss(for: text) : nil
            return .english(Candidate(text: text, source: source, annotation: annotation))
        }

        let merged = leading.compactMap { english($0, .englishCompletion) }
            + chinese.prefix(1)
            + promoted.compactMap { english($0, .englishCompletion) }
            + chinese.dropFirst()
            + trailing.compactMap { english($0.0, $0.1) }
        return Array(merged.prefix(Self.maxCandidates))
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
        baseState.mode == .chinese
            && baseState.candidatePageIndex == 0
            && input.count >= Self.minimumInputLength
            && input.allSatisfy { $0.isASCII && $0.isLowercase }
    }

    private func translationsOfFirstCandidate() -> [String] {
        guard let first = baseState.candidates.first?.text, first.count >= 2 else {
            return []
        }
        return Array(dictionary.translations(for: first).prefix(Self.maxTranslations))
    }
}
