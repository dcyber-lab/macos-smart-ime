import XCTest
@testable import EnglishEngine
import SharedModels

final class EnglishLexiconTests: XCTestCase {
    func testBundledLexiconIsLarge() {
        XCTAssertGreaterThanOrEqual(EnglishLexicon.bundled.count, 30000)
    }

    func testCompletionsAreOrderedByFrequency() {
        let lexicon = EnglishLexicon(wordsByFrequency: ["the", "they", "then", "apple", "theory"])

        XCTAssertEqual(lexicon.completions(forPrefix: "the", limit: 9), ["the", "they", "then", "theory"])
        XCTAssertEqual(lexicon.completions(forPrefix: "the", limit: 2), ["the", "they"])
        XCTAssertEqual(lexicon.completions(forPrefix: "zzz", limit: 9), [])
    }

    func testBundledLexiconCoversCommonAndTechnicalWords() {
        let lexicon = EnglishLexicon.bundled

        XCTAssertEqual(lexicon.completions(forPrefix: "th", limit: 3), ["the", "that", "this"])
        XCTAssertTrue(lexicon.completions(forPrefix: "gith", limit: 9).contains("github"))
        XCTAssertTrue(lexicon.completions(forPrefix: "deplo", limit: 9).contains("deployment"))
    }

    func testBundledLexiconExcludesProfanity() {
        XCTAssertFalse(EnglishLexicon.bundled.completions(forPrefix: "fuc", limit: 50).contains("fuck"))
    }
}

final class BasicEnglishEngineTests: XCTestCase {
    private let lexicon = EnglishLexicon(wordsByFrequency: ["catch", "cat", "category", "help", "hello"])

    func testTypedTextIsFirstCandidate() {
        let engine = BasicEnglishEngine(lexicon: lexicon)

        let update = type("cat", into: engine)

        XCTAssertEqual(update.state.candidates.map(\.text), ["cat", "catch", "category"])
    }

    func testSpaceCommitsTypedTextInsteadOfMoreFrequentCompletion() {
        let engine = BasicEnglishEngine(lexicon: lexicon)
        type("cat", into: engine)

        let update = engine.process(key(49, " "))

        XCTAssertEqual(update.commitText, "cat ")
        XCTAssertTrue(update.state.compositionText.isEmpty)
    }

    func testSpaceCommitsHighlightedCandidate() {
        let engine = BasicEnglishEngine(lexicon: lexicon)
        type("hel", into: engine)

        _ = engine.highlightCandidate(at: 1)
        let update = engine.process(key(49, " "))

        XCTAssertEqual(update.commitText, "help ")
    }

    func testNumberSelectionCommitsCompletion() {
        let engine = BasicEnglishEngine(lexicon: lexicon)
        type("hel", into: engine)

        let update = engine.selectCandidate(at: 2)

        XCTAssertEqual(update.commitText, "hello")
    }

    func testNoCandidatesWhenNothingCompletes() {
        let engine = BasicEnglishEngine(lexicon: lexicon)

        let update = type("xyz", into: engine)

        XCTAssertEqual(update.state.compositionText, "xyz")
        XCTAssertTrue(update.state.candidates.isEmpty)
    }

    @discardableResult
    private func type(_ text: String, into engine: BasicEnglishEngine) -> InputSessionUpdate {
        var update = engine.process(key(0, ""))
        for character in text {
            update = engine.process(key(0, String(character)))
        }
        return update
    }

    private func key(_ keyCode: UInt16, _ characters: String) -> InputKeyEvent {
        InputKeyEvent(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: characters)
    }
}
