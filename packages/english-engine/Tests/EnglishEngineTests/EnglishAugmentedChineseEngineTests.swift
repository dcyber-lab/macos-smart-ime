import XCTest
@testable import EnglishEngine
import SharedModels
import UserData

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

    func testNonPinyinPrefixCompletionIsPromotedToSecond() {
        fake.candidatesByInput["gith"] = ["个", "各"]

        let update = type("gith")

        XCTAssertEqual(texts(update), ["个", "github", "各"])
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "个", "Space still commits the first Chinese candidate")
    }

    func testShortInputIsNotPromoted() {
        fake.candidatesByInput["dep"] = ["得票", "地平"]

        XCTAssertEqual(texts(type("dep")), ["得票", "地平", "deploy", "deployed", "deployment"])
    }

    func testCompletePinyinIsNotPromoted() {
        fake.candidatesByInput["wome"] = ["我么", "我们"]

        XCTAssertEqual(texts(type("wome")), ["我么", "我们", "women", "womens", "womenswear"])
    }

    func testUnfinishedPinyinIsTranslated() {
        fake.candidatesByInput["shujuk"] = ["数据库", "数据卡"]

        XCTAssertEqual(texts(type("shujuk")), ["数据库", "数据卡", "database"])
    }

    func testAbbreviatedPinyinIsTranslated() {
        fake.candidatesByInput["sjk"] = ["数据库", "手机卡"]

        XCTAssertEqual(texts(type("sjk")), ["数据库", "手机卡", "database"])
    }

    func testRareExactWordIsNotPlacedFirst() {
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexiconWithRareTail(), dictionary: dictionary)
        fake.candidatesByInput["dep"] = ["得票", "地平"]

        XCTAssertEqual(texts(type("dep")), ["得票", "地平", "deploy"], "rare \"dep\" is dropped; common completions stay appended")
    }

    func testRareCompletionsOfUnfinishedPinyinAreHidden() {
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexiconWithRareTail(), dictionary: dictionary)
        fake.candidatesByInput["shuj"] = ["数据"]

        XCTAssertEqual(texts(type("shuj")), ["数据"])
    }

    func testRareWordsAllowedForLongNonPinyinInput() {
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexiconWithRareTail(), dictionary: dictionary)
        fake.candidatesByInput["kuber"] = ["哭吧"]

        XCTAssertEqual(texts(type("kuber")), ["哭吧", "kubernetes"], "rare words are appended, never promoted")
    }

    /// "dep", "shuji", and "kubernetes" sit past the common-word limit.
    private func lexiconWithRareTail() -> EnglishLexicon {
        let filler = (0..<EnglishLexicon.commonRankLimit).map { "filler\($0)" }
        return EnglishLexicon(wordsByFrequency: ["deploy"] + filler + ["dep", "shuji", "kubernetes"])
    }

    func testExactWordUsesDisplayForm() {
        engine = EnglishAugmentedChineseEngine(
            base: fake,
            lexicon: EnglishLexicon(wordsByFrequency: ["hello"], supplement: ["GitHub"]),
            dictionary: dictionary
        )
        fake.candidatesByInput["github"] = ["个"]

        XCTAssertEqual(texts(type("github")), ["GitHub", "个"])
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

    // MARK: Glosses

    func testEnglishWordsGetGlossesButTranslationsDoNot() {
        engine = EnglishAugmentedChineseEngine(
            base: fake,
            lexicon: lexicon,
            dictionary: dictionary,
            glossary: EnglishGlossary(glosses: ["deploy": "部署", "deployment": "部署", "database": "数据库"])
        )
        fake.candidatesByInput["deploy"] = ["得票"]
        let words = type("deploy").state.candidates

        XCTAssertEqual(words.first?.text, "deploy")
        XCTAssertEqual(words.first?.annotation, "部署")
        XCTAssertNil(words.first { $0.text == "得票" }?.annotation)

        engine.reset()
        fake.candidatesByInput["shujuku"] = ["数据库"]
        let translation = type("shujuku").state.candidates.first { $0.text == "database" }

        XCTAssertEqual(translation?.source, .englishTranslation)
        XCTAssertNil(translation?.annotation)
    }

    // MARK: Preedit

    func testNonPinyinInputShowsRawInputAsPreedit() {
        fake.candidatesByInput["good"] = ["够殴打"]
        fake.preeditByInput["good"] = "go o d"

        XCTAssertEqual(type("good").state.compositionText, "good")
    }

    func testPinyinKeepsSyllableSegmentation() {
        fake.candidatesByInput["shujuku"] = ["数据库"]
        fake.preeditByInput["shujuku"] = "shu ju ku"

        XCTAssertEqual(type("shujuku").state.compositionText, "shu ju ku")
    }

    func testPartiallyConvertedInputKeepsLibrimePreedit() {
        fake.candidatesByInput["zgrm"] = ["人民"]
        fake.preeditByInput["zgrm"] = "中国r m"

        XCTAssertEqual(type("zgrm").state.compositionText, "中国r m")
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

        let highlighted = engine.highlightCandidate(at: 1)
        let update = engine.process(key(49, " "))

        XCTAssertEqual(highlighted.state.selectedCandidateIndex, 1)
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

    // MARK: Learning

    func testPickedCompletionLeadsNonPinyinInput() {
        let history = learningEngine()
        fake.candidatesByInput["gith"] = ["个", "各"]
        type("gith")
        XCTAssertEqual(engine.selectCandidate(at: 1).commitText, "github")

        XCTAssertEqual(texts(type("gith")), ["github", "个", "各"])
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "github")
        XCTAssertEqual(history.words(withPrefix: "git", limit: 9), ["github"])
    }

    func testOnePickDoesNotDisplaceChineseForPinyin() {
        learningEngine()
        fake.candidatesByInput["shujuku"] = ["数据库", "书局", "数据"]
        type("shujuku")
        XCTAssertEqual(engine.selectCandidate(at: 3).commitText, "database")

        XCTAssertEqual(texts(type("shujuku")), ["数据库", "database", "书局", "数据"])
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "数据库")
    }

    func testTwoPicksLeadForPinyin() {
        learningEngine()
        fake.candidatesByInput["shujuku"] = ["数据库", "书局", "数据"]
        type("shujuku")
        engine.selectCandidate(at: 3)
        type("shujuku")
        XCTAssertEqual(engine.selectCandidate(at: 1).commitText, "database")

        XCTAssertEqual(texts(type("shujuku")), ["database", "数据库", "书局", "数据"])
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "database")
    }

    func testPickingChineseTakesTheLeadBack() {
        learningEngine()
        fake.candidatesByInput["shujuku"] = ["数据库", "书局"]
        for index in [2, 1] {
            type("shujuku")
            engine.selectCandidate(at: index) // database, twice
        }
        for _ in 0..<2 {
            XCTAssertEqual(texts(type("shujuku")).first, "database")
            XCTAssertEqual(engine.selectCandidate(at: 1).commitText, "数据库")
        }

        XCTAssertEqual(texts(type("shujuku")), ["数据库", "database", "书局"])
    }

    func testPickingChineseDemotesLeadingEnglishWord() {
        let history = learningEngine()
        fake.candidatesByInput["hello"] = ["何乐", "喝了"]
        type("hello")
        XCTAssertEqual(engine.selectCandidate(at: 1).commitText, "何乐")

        XCTAssertEqual(texts(type("hello")), ["何乐", "hello", "喝了", "gladly"])
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "何乐")
        XCTAssertEqual(history.choices(for: "hello").chinese, 1, accuracy: 0.001, "Space on a leading Chinese candidate is not recorded")
    }

    func testLearnedWordsLeadCompletions() {
        let history = learningEngine()
        fake.candidatesByInput["deplo"] = ["的"]
        XCTAssertEqual(texts(type("deplo")), ["的", "deploy", "deployed", "deployment"])
        engine.reset()

        history.recordWord("deployment")

        XCTAssertEqual(texts(type("deplo")), ["的", "deployment", "deploy", "deployed"])
    }

    func testOrdinaryChineseTypingIsNotRecorded() {
        let history = learningEngine()
        fake.candidatesByInput["women"] = ["我们", "我门"]
        type("women")
        engine.process(key(49, " "))
        type("women")
        engine.selectCandidate(at: 1)

        XCTAssertEqual(history.choices(for: "women"), .empty)
    }

    func testReturnIsNotRecorded() {
        let history = learningEngine()
        fake.candidatesByInput["hello"] = ["何乐"]
        type("hello")
        XCTAssertEqual(engine.process(key(36, "\r")).commitText, "hello")

        XCTAssertEqual(history.choices(for: "hello"), .empty)
        XCTAssertEqual(texts(type("hello")).first, "hello")
    }

    func testPickThatNoLongerFitsIsIgnored() {
        let history = learningEngine()
        history.recordChoice(input: "shujuku", english: "databank")
        fake.candidatesByInput["shujuku"] = ["数据库", "书局"]

        XCTAssertEqual(texts(type("shujuku")), ["数据库", "书局", "database"])
    }

    func testWordLeftOutOfSecondPlaceStillFollowsChinese() {
        let history = learningEngine()
        for pick in ["helper", "helper", "helpful", nil, nil, nil] {
            history.recordChoice(input: "help", english: pick)
        }
        fake.candidatesByInput["help"] = ["黑"]

        XCTAssertEqual(texts(type("help")), ["黑", "helper", "helpful", "help"])
    }

    // MARK: User translations and missing translations

    func testUserTranslationReplacesTheBuiltInOne() {
        let user = UserTranslations()
        user.addLearned("数据库", translations: ["DB"])
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexicon, dictionary: dictionary, userTranslations: user)
        fake.candidatesByInput["shujuku"] = ["数据库", "书局"]

        XCTAssertEqual(texts(type("shujuku")), ["数据库", "书局", "DB"])
    }

    func testUserTranslationFillsAWordWithoutOne() {
        let user = UserTranslations()
        user.addLearned("灰度环境", translations: ["staging environment"])
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexicon, dictionary: dictionary, userTranslations: user)
        fake.candidatesByInput["huiduhuanjing"] = ["灰度环境"]

        XCTAssertEqual(texts(type("huiduhuanjing")), ["灰度环境", "staging environment"])
    }

    func testCommittedWordWithoutTranslationIsCounted() {
        let misses = missCountingEngine()
        fake.candidatesByInput["huiduhuanjing"] = ["灰度环境", "灰度"]
        fake.candidatesByInput["feishu"] = ["飞书", "非书"]

        type("huiduhuanjing")
        XCTAssertEqual(engine.process(key(49, " ")).commitText, "灰度环境")
        type("feishu")
        XCTAssertEqual(engine.selectCandidate(at: 1).commitText, "非书")

        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9).map(\.text).sorted(), ["灰度环境", "非书"])
    }

    func testTranslatedAndNonWordCommitsAreNotCounted() {
        let misses = missCountingEngine()
        fake.candidatesByInput["shujuku"] = ["数据库"]
        fake.candidatesByInput["wox"] = ["我"]
        fake.candidatesByInput["neihe"] = ["内核，"]
        fake.candidatesByInput["qiyifenzhongdehuiyi"] = ["七一分钟的会议"]
        fake.candidatesByInput["huidu"] = ["灰度"]

        for input in ["shujuku", "wox", "neihe", "qiyifenzhongdehuiyi"] {
            type(input)
            XCTAssertNotNil(engine.process(key(49, " ")).commitText)
        }
        type("huidu")
        XCTAssertEqual(engine.process(key(36, "\r")).commitText, "huidu", "Return commits the raw letters")

        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9), [])
    }

    @discardableResult
    private func missCountingEngine() -> TranslationMisses {
        let misses = TranslationMisses()
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexicon, dictionary: dictionary, misses: misses)
        return misses
    }

    @discardableResult
    private func learningEngine() -> CandidateHistory {
        let history = CandidateHistory()
        engine = EnglishAugmentedChineseEngine(base: fake, lexicon: lexicon, dictionary: dictionary, history: history)
        return history
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
    /// Mimics librime's syllable-segmented preedit, e.g. "good" -> "go o d".
    var preeditByInput: [String: String] = [:]
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
            compositionText: preeditByInput[input] ?? input,
            candidates: candidates.map { Candidate(text: $0, source: .rime) },
            selectedCandidateIndex: candidates.isEmpty ? nil : highlightedIndex,
            candidatePageIndex: pageIndex
        )
        return InputSessionUpdate(handled: handled, state: state, commitText: commitText)
    }
}
