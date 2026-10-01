import XCTest
@testable import IMEHostCore
import UserData

final class IntelligenceRecorderTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "IntelligenceRecorderTests"
    private var recorder: IntelligenceRecorder!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntelligenceRecorderTests-\(UUID().uuidString)")
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        recorder = IntelligenceRecorder(
            settings: IntelligenceSettings(defaults: defaults),
            memory: InputMemory(fileURL: directory.appendingPathComponent("input-memory.json")),
            journal: InputJournal(directoryURL: directory.appendingPathComponent("journal"))
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
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

    private func type(_ sentence: String, in app: String) {
        recorder.commit(sentence, app: app, secureInput: false)
        recorder.endSentence()
    }

    private func journalTexts() -> [String] {
        recorder.journal.flush()
        return recorder.journal.entries(days: 30).map(\.text).reversed()
    }
}
