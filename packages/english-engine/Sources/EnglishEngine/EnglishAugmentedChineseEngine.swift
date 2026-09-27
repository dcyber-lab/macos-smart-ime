import Foundation
import SharedModels

/// Wraps a Chinese engine and merges English word and translation candidates into its candidate list.
public final class EnglishAugmentedChineseEngine: ChineseInputEngine {
    private static let spaceKeyCode: UInt16 = 49
    private static let maxCandidates = 9
    private static let maxWordCandidates = 3
    private static let maxTranslations = 2
    private static let minimumInputLength = 3

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
    private var baseState = CompositionState()
    private var entries: [Entry] = []
    private var highlight = Highlight.automatic

    public init(
        base: ChineseInputEngine,
        lexicon: EnglishLexicon = .bundled,
        dictionary: ChineseEnglishDictionary = .bundled
    ) {
        self.base = base
        self.lexicon = lexicon
        self.dictionary = dictionary
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
        let isWord = lexicon.contains(input)
        let completions = lexicon
            .completions(forPrefix: input, limit: Self.maxWordCandidates + 1)
            .filter { $0 != input }
        let words = Array(((isWord ? [input] : []) + completions).prefix(Self.maxWordCandidates))
        let translations = isPinyin ? translationsOfFirstCandidate() : []

        // A finished English word that is not pinyin goes first so Space commits it.
        let leading = !isPinyin && isWord ? [input] : []
        let trailing = translations.map { ($0, CandidateSource.englishTranslation) }
            + words.filter { !leading.contains($0) }.map { ($0, CandidateSource.englishCompletion) }

        var seen = Set(baseState.candidates.map(\.text))
        func english(_ text: String, _ source: CandidateSource) -> Entry? {
            guard seen.insert(text).inserted else {
                return nil
            }
            return .english(Candidate(text: text, source: source, score: 0))
        }

        let merged = leading.compactMap { english($0, .englishCompletion) }
            + chinese
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
