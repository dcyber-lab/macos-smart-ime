import Foundation
import SharedModels

public final class IMEHostSessionStore {
    public private(set) var state: CompositionState

    public init(initialState: CompositionState = CompositionState()) {
        self.state = initialState
    }

    public func append(_ string: String) {
        guard !string.isEmpty else {
            return
        }

        state.rawInput.append(string)
        state.compositionText = state.rawInput
        state.candidates = placeholderCandidates(for: state.rawInput)
    }

    public func deleteBackward() {
        guard !state.rawInput.isEmpty else {
            return
        }

        state.rawInput.removeLast()
        state.compositionText = state.rawInput
        state.candidates = placeholderCandidates(for: state.rawInput)
    }

    public func commitTextIfReady() -> String? {
        guard !state.rawInput.isEmpty else {
            return nil
        }

        let committedText: String
        if state.rawInput == IMEHostConfiguration.deterministicTrigger {
            committedText = IMEHostConfiguration.deterministicCommitText
        } else {
            committedText = state.rawInput
        }

        state.recentText = committedText
        resetComposition()
        return committedText
    }

    public func resetComposition() {
        state.rawInput = ""
        state.compositionText = ""
        state.candidates = []
    }

    private func placeholderCandidates(for rawInput: String) -> [Candidate] {
        guard !rawInput.isEmpty else {
            return []
        }

        var candidates = [
            Candidate(text: rawInput, source: .placeholder, score: 1.0),
        ]

        if rawInput == IMEHostConfiguration.deterministicTrigger {
            candidates.insert(
                Candidate(
                    text: IMEHostConfiguration.deterministicCommitText,
                    source: .placeholder,
                    score: 2.0
                ),
                at: 0
            )
        }

        return candidates
    }
}
