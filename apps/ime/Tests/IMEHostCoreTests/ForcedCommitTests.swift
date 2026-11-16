import EnglishEngine
import SharedModels
import XCTest
@testable import IMEHostCore

/// A commit the client forces (focus moved, input source changed, the app took Return) inserts what Return
/// would, not the preedit librime splits into syllables.
final class ForcedCommitTests: XCTestCase {
    func testChineseModeCommitsWhatReturnCommits() {
        let rime = ReturnCommitsRawInput(rawInput: "women")
        let state = CompositionState(rawInput: "women", mode: .chinese, compositionText: "wo men")

        let text = IMEInputController.forcedCommitText(state: state, chinese: rime, english: nil)

        XCTAssertEqual(text, "women")
        XCTAssertEqual(rime.processedKeyCodes, [36])
    }

    func testEnglishModeCommitsTheTypedWord() {
        let english = BasicEnglishEngine(lexicon: EnglishLexicon(wordsByFrequency: ["test", "testing"]))
        for (keyCode, letter) in [(17, "t"), (14, "e"), (1, "s"), (17, "t")] as [(UInt16, String)] {
            _ = english.process(InputKeyEvent(keyCode: keyCode, characters: letter, charactersIgnoringModifiers: letter))
        }
        let state = CompositionState(rawInput: "test", mode: .english, compositionText: "test")

        XCTAssertEqual(IMEInputController.forcedCommitText(state: state, chinese: nil, english: english), "test")
    }

    func testFallsBackToRawInputWhenReturnCommitsNothing() {
        let rime = ReturnCommitsRawInput(rawInput: nil)
        let state = CompositionState(rawInput: "test", mode: .chinese, compositionText: "t e s t")

        XCTAssertEqual(IMEInputController.forcedCommitText(state: state, chinese: rime, english: nil), "test")
        XCTAssertEqual(IMEInputController.forcedCommitText(state: state, chinese: nil, english: nil), "test")
    }
}

/// Stands in for librime: Return commits the raw input.
private final class ReturnCommitsRawInput: ChineseInputEngine {
    let rawInput: String?
    private(set) var processedKeyCodes: [UInt16] = []

    init(rawInput: String?) {
        self.rawInput = rawInput
    }

    func process(_ event: InputKeyEvent) -> InputSessionUpdate {
        processedKeyCodes.append(event.keyCode)
        return InputSessionUpdate(handled: true, state: CompositionState(), commitText: event.keyCode == 36 ? rawInput : nil)
    }

    func selectCandidate(at index: Int) -> InputSessionUpdate {
        InputSessionUpdate(handled: false, state: CompositionState())
    }

    func highlightCandidate(at index: Int) -> InputSessionUpdate {
        InputSessionUpdate(handled: false, state: CompositionState())
    }

    func reset() {}
}
