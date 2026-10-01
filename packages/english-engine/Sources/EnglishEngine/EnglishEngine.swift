import Foundation
import SharedModels
import UserData

public final class BasicEnglishEngine: EnglishInputEngine {
    private static let maxCandidates = 9

    private let lexicon: EnglishLexicon
    private let glossary: EnglishGlossary
    private let history: CandidateHistory?
    private var buffer: String = ""
    private var candidates: [Candidate] = []
    private var highlightedIndex: Int?

    public init(lexicon: EnglishLexicon = .bundled, glossary: EnglishGlossary = .bundled, history: CandidateHistory? = nil) {
        self.lexicon = lexicon
        self.glossary = glossary
        self.history = history
    }

    public func process(_ event: InputKeyEvent) -> InputSessionUpdate {
        let characters = event.characters

        // Handle Backspace
        if event.keyCode == 51 { // macOS Backspace
            if !buffer.isEmpty {
                buffer.removeLast()
                refreshCandidates()
                return update(handled: true)
            } else {
                return update(handled: false)
            }
        }

        // Handle Return/Enter
        if event.keyCode == 36 || event.keyCode == 76 {
            if !buffer.isEmpty {
                let commitText = buffer
                clearBuffer()
                return update(handled: true, commitText: committed(commitText))
            }
            return update(handled: false)
        }

        // Handle Space
        if event.keyCode == 49 {
            if !buffer.isEmpty {
                // Commit the highlighted candidate, otherwise the first one (the typed text)
                let index = highlightedIndex ?? 0
                let commitText = candidates.indices.contains(index) ? candidates[index].text : buffer
                clearBuffer()
                return update(handled: true, commitText: committed(commitText) + " ")
            }
            return update(handled: false)
        }

        // Handle word characters (a-z)
        if characters.count == 1, let char = characters.first, char.isLetter {
            buffer.append(char.lowercased())
            refreshCandidates()
            return update(handled: true)
        }

        // Non-word characters commit the buffer first
        if !buffer.isEmpty {
            let commitText = buffer
            clearBuffer()
            // We return handled: false so the host can process the current event after our commit
            return update(handled: false, commitText: committed(commitText))
        }

        return update(handled: false)
    }

    public func selectCandidate(at index: Int) -> InputSessionUpdate {
        if candidates.indices.contains(index) {
            let commitText = candidates[index].text
            clearBuffer()
            return update(handled: true, commitText: committed(commitText))
        }
        return update(handled: true)
    }

    public func highlightCandidate(at index: Int) -> InputSessionUpdate {
        if candidates.indices.contains(index) {
            highlightedIndex = index
        }
        return update(handled: true)
    }

    public func reset() {
        clearBuffer()
    }

    private func committed(_ word: String) -> String {
        history?.recordWord(word, in: lexicon)
        return word
    }

    private func clearBuffer() {
        buffer = ""
        refreshCandidates()
    }

    private func update(handled: Bool, commitText: String? = nil) -> InputSessionUpdate {
        let state = CompositionState(
            rawInput: buffer,
            mode: .english,
            compositionText: buffer,
            candidates: candidates,
            selectedCandidateIndex: highlightedIndex
        )
        return InputSessionUpdate(handled: handled, state: state, commitText: commitText)
    }

    private func refreshCandidates() {
        highlightedIndex = nil
        let completions = lexicon
            .completions(forPrefix: buffer, limit: Self.maxCandidates, preferring: history)
            .filter { $0 != buffer }
            .prefix(Self.maxCandidates - 1)
        guard !completions.isEmpty else {
            candidates = []
            return
        }

        // The typed text always comes first so Space never replaces it with a different word.
        candidates = ([buffer] + completions).map { word in
            Candidate(text: word, source: .englishCompletion, annotation: glossary.gloss(for: word))
        }
    }
}
