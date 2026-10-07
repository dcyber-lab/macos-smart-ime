import XCTest
@testable import EnglishEngine
import SharedModels
import UserData

final class EnglishLexiconTests: XCTestCase {
    func testBundledLexiconIsLarge() {
        XCTAssertGreaterThanOrEqual(EnglishLexicon.bundled.count, 100_000)
    }

    func testBundledLexiconLoadsQuickly() {
        // CPU time of this thread, not wall time: shared CI runners are often busy, and the wall-clock
        // bound of 1 s failed there at 1.05 and 1.6 s while this machine takes 0.33 s.
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let lexicon = EnglishLexicon(
            wordsByFrequency: bundledLines("wordlist"),
            supplement: bundledLines("supplement")
        )
        let seconds = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000_000

        XCTAssertGreaterThanOrEqual(lexicon.count, 100_000)
        // Catches a loader that got many times slower, not tuning; unoptimized test builds on slow
        // runners need the headroom, and release builds are several times faster.
        XCTAssertLessThan(seconds, 3.0, "loading took \(seconds)s of CPU time")
    }

    func testSupplementProvidesDisplayCasing() {
        let lexicon = EnglishLexicon.bundled

        XCTAssertEqual(lexicon.displayForm(of: "github"), "GitHub")
        XCTAssertEqual(lexicon.displayForm(of: "ios"), "iOS")
        XCTAssertEqual(lexicon.displayForm(of: "nodejs"), "Node.js")
        XCTAssertEqual(lexicon.displayForm(of: "hello"), "hello")
        XCTAssertTrue(lexicon.contains("GITHUB"), "matching is case-insensitive")
    }

    func testTechnicalTermsAreCompleted() {
        let lexicon = EnglishLexicon.bundled

        XCTAssertTrue(lexicon.completions(forPrefix: "refac", limit: 3).contains("refactor"))
        XCTAssertTrue(lexicon.completions(forPrefix: "kube", limit: 3).contains("Kubernetes"))
        XCTAssertTrue(lexicon.completions(forPrefix: "json", limit: 3).contains("JSON"))
    }

    func testSupplementRanksAheadOfRareWordsButBehindCommonOnes() {
        let lexicon = EnglishLexicon.bundled

        XCTAssertTrue(lexicon.completions(forPrefix: "typ", limit: 6).contains("TypeScript"))
        XCTAssertEqual(lexicon.completions(forPrefix: "th", limit: 3), ["the", "that", "this"])
    }

    func testSupplementDisplayReplacesWordListEntry() {
        let lexicon = EnglishLexicon(wordsByFrequency: ["the", "github"], supplement: ["GitHub"])

        XCTAssertEqual(lexicon.count, 2)
        XCTAssertEqual(lexicon.completions(forPrefix: "git", limit: 3), ["GitHub"])
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
        XCTAssertTrue(lexicon.completions(forPrefix: "gith", limit: 9).contains("GitHub"))
        XCTAssertTrue(lexicon.completions(forPrefix: "deplo", limit: 9).contains("deployment"))
    }

    func testBundledLexiconExcludesProfanity() {
        XCTAssertFalse(EnglishLexicon.bundled.completions(forPrefix: "fuc", limit: 50).contains("fuck"))
    }

    private func bundledLines(_ name: String) -> [String] {
        let url = Bundle.module.url(forResource: name, withExtension: "txt")!
        return try! String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
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

    func testCompletionsCarryGlosses() {
        let engine = BasicEnglishEngine(lexicon: lexicon, glossary: EnglishGlossary(glosses: ["category": "类别"]))

        let candidates = type("cat", into: engine).state.candidates

        XCTAssertEqual(candidates.first { $0.text == "category" }?.annotation, "类别")
        XCTAssertNil(candidates.first { $0.text == "catch" }?.annotation)
    }

    func testLearnedCompletionsComeAfterTypedText() {
        let history = CandidateHistory()
        history.recordWord("category")
        let engine = BasicEnglishEngine(lexicon: lexicon, history: history)

        XCTAssertEqual(type("cat", into: engine).state.candidates.map(\.text), ["cat", "category", "catch"])
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "cat ", "Space still commits the typed text")
    }

    func testCommitsRecordOnlyLexiconWords() {
        let history = CandidateHistory()
        let engine = BasicEnglishEngine(lexicon: lexicon, history: history)
        type("hel", into: engine)
        engine.selectCandidate(at: 2)
        type("xyz", into: engine)
        engine.process(key(49, " "))

        XCTAssertEqual(history.words(withPrefix: "hel", limit: 9), ["hello"])
        XCTAssertEqual(history.words(withPrefix: "xyz", limit: 9), [])
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
