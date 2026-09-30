import XCTest
@testable import IMEHostCore
import EnglishEngine
import UserData

@MainActor
final class TranslationLearnerTests: XCTestCase {
    private let suiteName = "TranslationLearnerTests"
    private let lexicon = EnglishLexicon(wordsByFrequency: ["staging", "environment", "kernel", "space", "zhang"])
    private let dictionary = ChineseEnglishDictionary(translations: ["数据库": ["database"]])
    private var defaults: UserDefaults!
    private var clock: LearnerClock!
    private var misses: TranslationMisses!
    private var userTranslations: UserTranslations!
    private var translator: FakeTermTranslator!
    private var learner: TranslationLearner!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        clock = LearnerClock()
        let clock = self.clock!
        misses = TranslationMisses(clock: { clock.date })
        userTranslations = UserTranslations()
        translator = FakeTermTranslator()
        let defaults = self.defaults!
        learner = TranslationLearner(
            misses: misses,
            userTranslations: userTranslations,
            dictionary: dictionary,
            lexicon: lexicon,
            translator: translator,
            settings: { TranslationLearningSettings(defaults: defaults) },
            clock: { clock.date }
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLearnsATranslationThatSurvivesTheRoundTrip() async {
        commit("灰度环境", times: 3)
        translator.results = ["灰度环境": TermTranslation(english: "Staging environment.", roundTrip: "灰度环境。")]

        let outcome = await learner.run()

        XCTAssertEqual(outcome, TranslationLearner.Outcome(learned: 1))
        XCTAssertEqual(userTranslations.translations(for: "灰度环境"), ["staging environment"])
        XCTAssertTrue(misses.isProcessed("灰度环境"))
        XCTAssertEqual(misses.lastRun, clock.date)
    }

    func testRejectsMismatchedRoundTripsAndNonTerms() async {
        commit("复盘", times: 3)
        commit("说来话长", times: 3)
        commit("行吧那就", times: 3)
        translator.results = [
            "复盘": TermTranslation(english: "review", roundTrip: "审查"),
            "说来话长": TermTranslation(english: "it is a long story to tell", roundTrip: "说来话长"),
            "行吧那就": TermTranslation(english: "行吧", roundTrip: "行吧那就"),
        ]

        let outcome = await learner.run()

        XCTAssertEqual(outcome, TranslationLearner.Outcome(rejected: 3))
        XCTAssertEqual(userTranslations.count, 0)
        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9), [], "each word is tried once")
    }

    func testKeepsNamesAndAcronymsAsTranslated() {
        XCTAssertEqual(learner.accepted(TermTranslation(english: "Zhang Wei", roundTrip: "张伟"), for: "张伟"), "Zhang Wei")
        XCTAssertEqual(learner.accepted(TermTranslation(english: "API gateway", roundTrip: "接口网关"), for: "接口网关"), "API gateway")
        XCTAssertEqual(learner.accepted(TermTranslation(english: "ByteDance", roundTrip: "字节跳动"), for: "字节跳动"), "ByteDance")
        XCTAssertEqual(learner.accepted(TermTranslation(english: "Kernel", roundTrip: "内核"), for: "内核"), "kernel")
    }

    func testSkipsWordsThatGainedATranslation() async {
        commit("数据库", times: 3)
        commit("飞书文档", times: 3)
        userTranslations.addLearned("飞书文档", translations: ["Feishu Docs"])

        let outcome = await learner.run()

        XCTAssertEqual(outcome, TranslationLearner.Outcome(skipped: 2))
        XCTAssertEqual(translator.requests, [])
        XCTAssertFalse(misses.isProcessed("数据库"))
    }

    func testFailedWordIsTriedAgain() async {
        commit("灰度环境", times: 3)

        _ = await learner.run()

        XCTAssertFalse(misses.isProcessed("灰度环境"))
        XCTAssertEqual(misses.candidates(minimumCount: 3, limit: 9).map(\.text), ["灰度环境"])
    }

    func testMissingLanguagesAreCheckedAgainWithinAnHour() async {
        commit("灰度环境", times: 3)
        translator.languagesInstalled = false

        let outcome = await learner.run()

        XCTAssertTrue(outcome.languagesMissing)
        XCTAssertNil(misses.lastRun)
        XCTAssertFalse(learner.isDue)
        clock.date += TranslationLearner.missingLanguagesRetryDelay
        XCTAssertTrue(learner.isDue)
    }

    func testIsDueNeedsThreeCommitsTheIntervalAndTheSetting() async {
        commit("灰度环境", times: 2)
        XCTAssertFalse(learner.isDue)
        commit("灰度环境", times: 1)
        XCTAssertTrue(learner.isDue)

        defaults.set(false, forKey: TranslationLearningSettings.enabledKey)
        XCTAssertFalse(learner.isDue)
        defaults.removeObject(forKey: TranslationLearningSettings.enabledKey)

        translator.results = ["灰度环境": TermTranslation(english: "staging environment", roundTrip: "灰度环境")]
        _ = await learner.run()
        commit("飞书文档", times: 3)
        XCTAssertFalse(learner.isDue, "ran less than a day ago")
        clock.date += TranslationLearningSettings.defaultInterval
        XCTAssertTrue(learner.isDue)
    }

    func testRunIfDueRunsInTheBackgroundOnce() async {
        commit("灰度环境", times: 3)
        translator.results = ["灰度环境": TermTranslation(english: "staging environment", roundTrip: "灰度环境")]

        let task = learner.runIfDue()
        XCTAssertNotNil(task)
        XCTAssertNil(learner.runIfDue(), "already running")
        let outcome = await task?.value

        XCTAssertEqual(outcome?.learned, 1)
        XCTAssertNil(learner.runIfDue(), "not due again until the interval passes")
    }

    func testSettingsDefaultsAndMinimumInterval() {
        let settings = TranslationLearningSettings(defaults: defaults)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.interval, 24 * 60 * 60)

        defaults.set(5, forKey: TranslationLearningSettings.intervalKey)
        XCTAssertEqual(TranslationLearningSettings(defaults: defaults).interval, 60)
        defaults.set(600, forKey: TranslationLearningSettings.intervalKey)
        XCTAssertEqual(TranslationLearningSettings(defaults: defaults).interval, 600)
    }

    private func commit(_ word: String, times: Int) {
        for _ in 0..<times {
            misses.record(word)
        }
    }
}

private final class LearnerClock: @unchecked Sendable {
    var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

private final class FakeTermTranslator: TermTranslator, @unchecked Sendable {
    var languagesInstalled = true
    /// Words without a result fail to translate.
    var results: [String: TermTranslation] = [:]
    private(set) var requests: [[String]] = []

    func translate(_ words: [String]) async -> [TermTranslation?]? {
        requests.append(words)
        return languagesInstalled ? words.map { results[$0] } : nil
    }
}
