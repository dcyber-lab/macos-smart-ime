import XCTest
@testable import IMEHostCore
import UserData

@MainActor
final class IntelligenceRecorderTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "IntelligenceRecorderTests"
    private var recorder: IntelligenceRecorder!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntelligenceRecorderTests-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        recorder = IntelligenceRecorder(
            settings: IntelligenceSettings(defaults: defaults),
            memory: InputMemory(fileURL: directory.appendingPathComponent("input-memory.json")),
            journal: InputJournal(directoryURL: directory.appendingPathComponent("journal")),
            later: { $0() }
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func testNothingIsLearnedUntilEnabled() {
        type("这个功能下周上线。", in: "slack")
        recorder.memory.flush()

        XCTAssertNil(recorder.memory.profile(for: "slack"))
        XCTAssertTrue(journalTexts().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testEnabledLearningKeepsStatisticsAndTheJournal() {
        recorder.settings.isLearningEnabled = true
        type("这个功能下周上线。", in: "slack")

        XCTAssertEqual(recorder.memory.profile(for: "slack")?.hanCharacters ?? 0, 8, accuracy: 0.01)
        XCTAssertEqual(journalTexts(), ["这个功能下周上线。"])
        XCTAssertEqual(recorder.recentSentences(in: "slack"), ["这个功能下周上线。"])
    }

    func testJournalOffKeepsOnlyStatistics() {
        recorder.settings.isLearningEnabled = true
        recorder.settings.isJournalEnabled = false
        type("这个功能下周上线。", in: "slack")

        XCTAssertNotNil(recorder.memory.profile(for: "slack"))
        XCTAssertTrue(journalTexts().isEmpty)
    }

    func testExcludedAppsSecureInputAndSensitiveSentencesAreSkipped() {
        recorder.settings.isLearningEnabled = true
        recorder.settings.toggleExcluded("com.tencent.xinWeChat")
        type("私聊内容。", in: "com.tencent.xinWeChat")
        type("ls -la。", in: "com.apple.Terminal")
        type("验证码是 482913。", in: "slack")
        recorder.commit("密码。", app: "slack", secureInput: true)
        recorder.commit("未知应用。", app: nil, secureInput: false)
        recorder.endSentence()

        XCTAssertTrue(journalTexts().isEmpty)
        XCTAssertNil(recorder.memory.profile(for: "com.tencent.xinWeChat"))
        XCTAssertNil(recorder.memory.profile(for: "slack"))
    }

    func testAllowingADefaultExcludedAppRecordsThere() {
        recorder.settings.isLearningEnabled = true
        recorder.settings.toggleExcluded("com.mitchellh.ghostty")
        type("帮我看下这个报错。", in: "com.mitchellh.ghostty")

        XCTAssertEqual(journalTexts(), ["帮我看下这个报错。"])
        XCTAssertEqual(recorder.settings.allowedApps, ["com.mitchellh.ghostty"])
        XCTAssertFalse(recorder.settings.effectiveExcludedApps.contains("com.mitchellh.ghostty"))

        recorder.settings.toggleExcluded("com.mitchellh.ghostty")
        XCTAssertTrue(recorder.settings.isExcluded("com.mitchellh.ghostty"))
    }

    func testLeavingForAnExcludedAppClosesTheSentence() {
        recorder.settings.isLearningEnabled = true
        recorder.commit("写到一半", app: "slack", secureInput: false)
        recorder.commit("pwd", app: "com.apple.Terminal", secureInput: false)

        XCTAssertEqual(journalTexts(), ["写到一半"])
    }

    func testClearForgetsEverything() {
        recorder.settings.isLearningEnabled = true
        type("这个功能下周上线。", in: "slack")
        recorder.memory.flush()

        recorder.clear()

        XCTAssertNil(recorder.memory.profile(for: "slack"))
        XCTAssertTrue(journalTexts().isEmpty)
        XCTAssertTrue(recorder.recentSentences(in: "slack").isEmpty)
    }

    func testSettingsDefaults() {
        let settings = IntelligenceSettings(defaults: defaults)
        XCTAssertFalse(settings.isLearningEnabled)
        XCTAssertTrue(settings.isJournalEnabled)
        XCTAssertEqual(settings.retentionDays, 30)
        defaults.set(0, forKey: IntelligenceSettings.retentionKey)
        XCTAssertEqual(settings.retentionDays, 1)
        settings.toggleExcluded("mail")
        XCTAssertEqual(settings.excludedApps, ["mail"])
        settings.toggleExcluded("mail")
        XCTAssertEqual(settings.excludedApps, [])
    }

    func testSentenceEndReadsTheTextBeforeItOnce() {
        recorder.settings.isLearningEnabled = true
        var reads = 0
        let field = { () -> String? in reads += 1; return "发布计划\n这个功能下周上线。" }
        recorder.commit("这个功能", app: "notes", secureInput: false, readContext: field)
        recorder.commit("下周上线。", app: "notes", secureInput: false, readContext: field)

        XCTAssertEqual(reads, 1, "only the commit that ends the sentence reads the client")
        XCTAssertEqual(journalEntries().first?.context, "发布计划")
        XCTAssertEqual(recorder.contextStats["notes"]?.reads, 1)
        XCTAssertEqual(recorder.contextStats["notes"]?.found, 1)
    }

    func testSentencesClosedByAPauseOrSwitchAreNotRead() {
        recorder.settings.isLearningEnabled = true
        var reads = 0
        recorder.commit("写到一半", app: "notes", secureInput: false, readContext: { reads += 1; return "x" })
        recorder.endSentence()

        XCTAssertEqual(reads, 0)
        XCTAssertNil(journalEntries().first?.context)
    }

    func testSensitiveOrEmptyContextIsDropped() {
        XCTAssertNil(IntelligenceRecorder.context(before: "收到。", in: "验证码 482913\n收到。"))
        XCTAssertNil(IntelligenceRecorder.context(before: "收到。", in: "收到。"))
        XCTAssertNil(IntelligenceRecorder.context(before: "收到。", in: nil))
        XCTAssertEqual(IntelligenceRecorder.context(before: "B。", in: String(repeating: "长", count: 500) + "A。B。")?.count, IntelligenceRecorder.contextLimit)
    }

    func testASlowAppIsNotReadAgain() {
        recorder.settings.isLearningEnabled = true
        var reads = 0
        let slow = { () -> String? in reads += 1; Thread.sleep(forTimeInterval: IntelligenceRecorder.slowRead + 0.05); return "前文" }
        type("第一句。", in: "electron", readContext: slow)
        type("第二句。", in: "electron", readContext: slow)

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(recorder.contextStats["electron"]?.isStopped, true)
        XCTAssertEqual(journalEntries().map(\.text), ["第二句。", "第一句。"], "sentences are still journaled")
    }

    func testJournalOffNeverReadsTheClient() {
        recorder.settings.isLearningEnabled = true
        recorder.settings.isJournalEnabled = false
        var reads = 0
        type("这个功能下周上线。", in: "notes", readContext: { reads += 1; return "x" })

        XCTAssertEqual(reads, 0)
    }

    private func type(_ sentence: String, in app: String, readContext: (() -> String?)? = nil) {
        recorder.commit(sentence, app: app, secureInput: false, readContext: readContext)
        recorder.endSentence()
    }

    private func journalEntries() -> [InputJournal.Entry] {
        recorder.journal.flush()
        return recorder.journal.entries(days: 30)
    }


    private func journalTexts() -> [String] {
        recorder.journal.flush()
        return recorder.journal.entries(days: 30).map(\.text).reversed()
    }
}
