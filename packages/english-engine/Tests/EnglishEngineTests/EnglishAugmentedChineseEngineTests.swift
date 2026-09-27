import XCTest
@testable import EnglishEngine
import SharedModels

final class EnglishAugmentedChineseEngineTests: XCTestCase {
    private let lexicon = EnglishLexicon(wordsByFrequency: [
        "the", "we", "hello", "help", "helper", "helpful", "deploy", "deployed", "deployment",
        "github", "women", "womens", "womenswear", "database",
    ])
    private let dictionary = ChineseEnglishDictionary(translations: [
        "数据库": ["database"],
        "我们": ["we", "us"],
        "西安": ["Xi'an"],
        "何乐": ["gladly"],
    ])

    private var fake: FakeChineseEngine!
    private var engine: EnglishAugmentedChineseEngine!

    override func setUp() {
        super.setUp()
        fake = FakeChineseEngine()
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexicon, dictionary: dictionary)
    }

    // MARK: English word candidates

    func testExactNonPinyinWordGoesFirst() {
        fake.candidatesByInput["hello"] = ["何乐", "喝了"]

        let update = type("hello")

        XCTAssertEqual(texts(update), ["hello", "何乐", "喝了"])
        XCTAssertEqual(update.state.selectedCandidateIndex, 0)
    }

    func testDeployIsOfferedInChineseMode() {
        fake.candidatesByInput["deploy"] = ["的"]

        XCTAssertEqual(texts(type("deploy")), ["deploy", "的", "deployed", "deployment"])
    }

    func testPrefixCompletionIsAppended() {
        fake.candidatesByInput["gith"] = ["个", "各"]

        XCTAssertEqual(texts(type("gith")), ["个", "各", "github"])
    }

    func testPinyinInputKeepsChineseFirst() {
        fake.candidatesByInput["women"] = ["我们", "我门"]
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexicon, dictionary: ChineseEnglishDictionary(translations: [:]))

        let update = type("women")

        XCTAssertEqual(texts(update), ["我们", "我门", "women", "womens", "womenswear"])
        XCTAssertEqual(update.state.selectedCandidateIndex, 0)
    }

    func testNoEnglishMatchShowsOnlyChinese() {
        fake.candidatesByInput["nihao"] = ["你好", "拟好"]

        XCTAssertEqual(texts(type("nihao")), ["你好", "拟好"])
    }

    func testShortInputHasNoEnglishCandidates() {
        fake.candidatesByInput["we"] = ["我", "为"]

        XCTAssertEqual(texts(type("we")), ["我", "为"])
    }

    func testDelimiterDisablesEnglishCandidates() {
        fake.candidatesByInput["xi'an"] = ["西安"]

        XCTAssertEqual(texts(type("xi'an")), ["西安"])
    }

    func testLaterPageHasNoEnglishCandidates() {
        fake.candidatesByInput["hello"] = ["何乐"]
        type("hello")

        fake.pageIndex = 1
        let update = engine.process(key(24, "="))

        XCTAssertEqual(texts(update), ["何乐"])
    }

    func testEnglishWordCandidatesAreCappedAtThree() {
        fake.candidatesByInput["help"] = ["黑"]

        let words = texts(type("help")).filter { $0 != "黑" }

        XCTAssertEqual(words, ["help", "helper", "helpful"])
    }

    // MARK: Translation candidates

    func testTranslationFollowsChineseCandidates() {
        fake.candidatesByInput["shujuku"] = ["数据库", "书局", "数据"]

        let update = type("shujuku")

        XCTAssertEqual(texts(update), ["数据库", "书局", "数据", "database"])
        XCTAssertEqual(update.state.candidates.last?.source, .englishTranslation)
    }

    func testSingleCharacterCandidateIsNotTranslated() {
        fake.candidatesByInput["shu"] = ["书", "数据库"]

        XCTAssertEqual(texts(type("shu")), ["书", "数据库"])
    }

    func testNonPinyinInputIsNotTranslated() {
        fake.candidatesByInput["hello"] = ["何乐"]

        XCTAssertFalse(texts(type("hello")).contains("gladly"))
    }

    func testWordWithoutDictionaryEntryShowsNoTranslation() {
        fake.candidatesByInput["nihao"] = ["你好"]

        XCTAssertEqual(texts(type("nihao")), ["你好"])
    }

    func testFullPageIsCappedAtNine() {
        fake.candidatesByInput["women"] = ["我们", "我门", "窝们", "沃们", "握们"]

        XCTAssertEqual(
            texts(type("women")),
            ["我们", "我门", "窝们", "沃们", "握们", "we", "us", "women", "womens"]
        )
    }

    func testTranslationEqualToEnglishWordAppearsOnce() {
        fake.candidatesByInput["women"] = ["我们"]
        engine = EnglishAugmentedChineseEngine(
            base: fake,
            lexicon: lexicon,
            dictionary: ChineseEnglishDictionary(translations: ["我们": ["women"]])
        )

        let update = type("women")

        XCTAssertEqual(texts(update), ["我们", "women", "womens", "womenswear"])
        XCTAssertEqual(update.state.candidates[1].source, .englishTranslation)
    }

    // MARK: Selection

    func testSpaceCommitsFirstPlaceEnglishWord() {
        fake.candidatesByInput["hello"] = ["何乐"]
        type("hello")

        let update = engine.process(key(49, " "))

        XCTAssertEqual(update.commitText, "hello")
        XCTAssertTrue(update.state.compositionText.isEmpty)
        XCTAssertTrue(update.state.candidates.isEmpty)
        XCTAssertEqual(fake.resetCount, 1)
    }

    func testSpaceCommitsFirstPlaceChineseCandidate() {
        fake.candidatesByInput["women"] = ["我们"]
        type("women")

        let update = engine.process(key(49, " "))

        XCTAssertEqual(update.commitText, "我们")
    }

    func testNumberKeySelectsEnglishCandidate() {
        fake.candidatesByInput["gith"] = ["个"]
        type("gith")

        let update = engine.selectCandidate(at: 1)

        XCTAssertEqual(update.commitText, "github")
        XCTAssertTrue(fake.selectedPageIndices.isEmpty)
    }

    func testNumberKeySelectsChineseCandidateAfterLeadingEnglish() {
        fake.candidatesByInput["hello"] = ["何乐", "喝了"]
        type("hello")

        let update = engine.selectCandidate(at: 2)

        XCTAssertEqual(fake.selectedPageIndices, [1])
        XCTAssertEqual(update.commitText, "喝了")
    }

    func testNumberKeySelectsTranslation() {
        fake.candidatesByInput["shujuku"] = ["数据库", "书局"]
        type("shujuku")

        let update = engine.selectCandidate(at: 2)

        XCTAssertEqual(update.commitText, "database")
        XCTAssertTrue(update.state.compositionText.isEmpty)
    }

    func testHighlightedEnglishCandidateCommittedWithSpace() {
        fake.candidatesByInput["gith"] = ["个", "各"]
        type("gith")

        let highlighted = engine.highlightCandidate(at: 2)
        let update = engine.process(key(49, " "))

        XCTAssertEqual(highlighted.state.selectedCandidateIndex, 2)
        XCTAssertEqual(update.commitText, "github")
    }

    func testHighlightingChineseAfterLeadingEnglishMapsIndex() {
        fake.candidatesByInput["hello"] = ["何乐", "喝了"]
        type("hello")

        let highlighted = engine.highlightCandidate(at: 2)

        XCTAssertEqual(fake.highlightedIndex, 1)
        XCTAssertEqual(highlighted.state.selectedCandidateIndex, 2)
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "喝了")
    }

    func testReturnCommitsRawInput() {
        fake.candidatesByInput["hello"] = ["何乐"]
        type("hello")

        let update = engine.process(key(36, "\r"))

        XCTAssertEqual(update.commitText, "hello")
        XCTAssertEqual(fake.processedKeyCodes.last, 36)
    }

    // MARK: Helpers

    @discardableResult
    private func type(_ text: String) -> InputSessionUpdate {
        var update = InputSessionUpdate(handled: false, state: CompositionState())
        for character in text {
            update = engine.process(key(0, String(character)))
        }
        return update
    }

    private func texts(_ update: InputSessionUpdate) -> [String] {
        update.state.candidates.map(\.text)
    }

    private func key(_ keyCode: UInt16, _ characters: String) -> InputKeyEvent {
        InputKeyEvent(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: characters)
    }
}

/// Minimal stand-in for `RimeBridgeEngine`: letters append, Space commits the highlight, Return commits raw input.
private final class FakeChineseEngine: ChineseInputEngine {
    var candidatesByInput: [String: [String]] = [:]
    var pageIndex = 0
    private(set) var input = ""
    private(set) var highlightedIndex = 0
    private(set) var selectedPageIndices: [Int] = []
    private(set) var processedKeyCodes: [UInt16] = []
    private(set) var resetCount = 0

    func process(_ event: InputKeyEvent) -> InputSessionUpdate {
        processedKeyCodes.append(event.keyCode)
        switch event.keyCode {
        case 49:
            return commitCandidate(at: highlightedIndex)
        case 36:
            let text = input
            clear()
            return update(commitText: text)
        case 24:
            return update()
        default:
            input += event.characters
            highlightedIndex = 0
            return update()
        }
    }

    func selectCandidate(at index: Int) -> InputSessionUpdate {
        selectedPageIndices.append(index)
        return commitCandidate(at: index)
    }

    func highlightCandidate(at index: Int) -> InputSessionUpdate {
        highlightedIndex = index
        return update()
    }

    func reset() {
        resetCount += 1
        clear()
    }

    private var candidates: [String] {
        candidatesByInput[input] ?? []
    }

    private func commitCandidate(at index: Int) -> InputSessionUpdate {
        guard candidates.indices.contains(index) else {
            return update(handled: false)
        }
        let text = candidates[index]
        clear()
        return update(commitText: text)
    }

    private func clear() {
        input = ""
        highlightedIndex = 0
        pageIndex = 0
    }

    private func update(handled: Bool = true, commitText: String? = nil) -> InputSessionUpdate {
        let state = CompositionState(
            rawInput: input,
            mode: .chinese,
            compositionText: input,
            candidates: candidates.map { Candidate(text: $0, source: .rime, score: 0) },
            selectedCandidateIndex: candidates.isEmpty ? nil : highlightedIndex,
            candidatePageIndex: pageIndex
        )
        return InputSessionUpdate(handled: handled, state: state, commitText: commitText)
    }
}
