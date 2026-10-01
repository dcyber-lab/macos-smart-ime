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

    // MARK: What is recorded

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

    func testJournalOffKeepsOnlyStatisticsAndNeverReadsTheClient() {
        recorder.settings.isLearningEnabled = true
        recorder.settings.isJournalEnabled = false
        var reads = 0
        type("这个功能下周上线。", in: "notes", readField: { reads += 1; return "x" })
        recorder.endLine(app: "notes", secureInput: false, readField: { reads += 1; return "x" })

        XCTAssertNotNil(recorder.memory.profile(for: "notes"))
        XCTAssertTrue(journalTexts().isEmpty)
        XCTAssertEqual(reads, 0)
    }

    func testExcludedAppsAndSecureInputAreSkippedAndSensitiveSpansMasked() {
        recorder.settings.isLearningEnabled = true
        recorder.settings.toggleExcluded("com.tencent.xinWeChat")
        type("私聊内容。", in: "com.tencent.xinWeChat")
        type("ls -la。", in: "com.apple.Terminal")
        recorder.commit("密码。", app: "slack", secureInput: true)
        recorder.commit("未知应用。", app: nil, secureInput: false)
        type("验证码是 482913。", in: "slack")

        XCTAssertEqual(journalTexts(), ["验证码是 〔数字〕。"])
        XCTAssertNil(recorder.memory.profile(for: "com.tencent.xinWeChat"))
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

    // MARK: Sentence boundaries

    func testLeavingTheFieldAndComingBackContinuesTheSentence() {
        recorder.settings.isLearningEnabled = true
        recorder.commit("麻烦帮忙看看吗", app: "seatalk", session: 1, secureInput: false)
        // The user switches to Chrome to copy a link (no commits there) and comes back.
        recorder.commit("注意时长", app: "seatalk", session: 1, secureInput: false)
        recorder.endLine(app: "seatalk", secureInput: false)

        XCTAssertEqual(journalTexts(), ["麻烦帮忙看看吗注意时长"])
    }

    func testAnotherFieldOrAppStartsANewSentence() {
        recorder.settings.isLearningEnabled = true
        recorder.commit("第一个框", app: "notes", session: 1, secureInput: false)
        recorder.commit("第二个框", app: "notes", session: 2, secureInput: false)
        recorder.commit("写到一半", app: "slack", session: 3, secureInput: false)
        recorder.commit("pwd", app: "com.apple.Terminal", session: 4, secureInput: false)

        XCTAssertEqual(journalTexts(), ["第一个框", "第二个框", "写到一半"])
    }

    // MARK: Reading the field

    func testReturnJournalsTheWholeLineAsTheAppHasIt() {
        recorder.settings.isLearningEnabled = true
        var reads = 0
        // Only these pieces went through the input method; the mention, link, and digits did not.
        recorder.commit("我们这边的pipeline报错，可以帮忙看看吗", app: "seatalk", secureInput: false)
        recorder.commit("注意时长，", app: "seatalk", secureInput: false)
        recorder.commit("mins内完成", app: "seatalk", secureInput: false)
        recorder.endLine(app: "seatalk", secureInput: false, readField: {
            reads += 1
            return "@DE-N-CDN 我们这边的pipeline报错，可以帮忙看看吗 https://space.example.io/p/f361f7a1e7fc9a478ed583b3ea4a9b659ebfd3c0 注意时长，10mins 内完成"
        })

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(journalTexts(), ["@DE-N-CDN 我们这边的pipeline报错，可以帮忙看看吗 〔链接〕 注意时长，10mins 内完成"])
        XCTAssertEqual(recorder.contextStats["seatalk"]?.found, 1)
    }

    func testReturnAfterOnlyPastingStillJournalsTheLine() {
        recorder.settings.isLearningEnabled = true
        recorder.endLine(app: "seatalk", secureInput: false, readField: { "上一条\n看这个 https://example.com/x" })

        XCTAssertEqual(journalEntries().map(\.text), ["看这个 〔链接〕"])
        XCTAssertEqual(journalEntries().first?.context, "上一条")
    }

    func testPunctuationTakesTheFullSentenceAndItsContextFromTheField() {
        recorder.settings.isLearningEnabled = true
        var reads = 0
        let field = { () -> String? in reads += 1; return "发布计划\n第1步。版本 2.3 已发布，10 点开会。" }
        recorder.commit("已发布，", app: "notes", secureInput: false, readField: field)
        recorder.commit("点开会。", app: "notes", secureInput: false, readField: field)

        XCTAssertEqual(reads, 1, "only the commit that ends the sentence reads the client")
        XCTAssertEqual(journalEntries().first?.text, "版本 2.3 已发布，10 点开会。")
        XCTAssertEqual(journalEntries().first?.context, "发布计划\n第1步。")
    }

    func testAFieldThatDoesNotMatchFallsBackToWhatWasTyped() {
        recorder.settings.isLearningEnabled = true
        type("这个功能下周上线。", in: "notes", readField: { "完全不相关的内容。" })

        XCTAssertEqual(journalTexts(), ["这个功能下周上线。"])
    }

    func testASlowAppIsNotReadAgain() {
        recorder.settings.isLearningEnabled = true
        var reads = 0
        let slow = { () -> String? in reads += 1; Thread.sleep(forTimeInterval: IntelligenceRecorder.slowRead + 0.05); return nil }
        type("第一句。", in: "electron", readField: slow)
        type("第二句。", in: "electron", readField: slow)

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(recorder.contextStats["electron"]?.isStopped, true)
        XCTAssertEqual(journalTexts(), ["第一句。", "第二句。"], "sentences are still journaled")
    }

    func testFieldParsing() {
        XCTAssertEqual(IntelligenceRecorder.line(endingAt: "甲\n乙 丙  "), .init(text: "乙 丙", context: "甲"))
        XCTAssertNil(IntelligenceRecorder.line(endingAt: "甲\n"))
        XCTAssertEqual(IntelligenceRecorder.sentence(endingAt: "一。二！三？"), .init(text: "三？", context: "一。二！"))
        XCTAssertEqual(IntelligenceRecorder.sentence(endingAt: "只有一句。"), .init(text: "只有一句。", context: nil))
        XCTAssertEqual(IntelligenceRecorder.sentence(endingAt: String(repeating: "长", count: 500) + "。短句。")?.context?.count, IntelligenceRecorder.contextLimit)
        XCTAssertNotNil(IntelligenceRecorder.consistent(.init(text: "@a 帮忙看看 10mins 内完成", context: nil), with: "帮忙看看mins内完成"))
        XCTAssertNil(IntelligenceRecorder.consistent(.init(text: "别的", context: nil), with: "这个功能下周上线"))
        XCTAssertEqual(IntelligenceRecorder.sentence(endingAt: "版本 v2.3 发布了。e.g. 这样。")?.text, "这样。")
        XCTAssertEqual(IntelligenceRecorder.sentence(endingAt: "Done. Ship v2.3 now.")?.text, "Ship v2.3 now.")
        XCTAssertNotNil(IntelligenceRecorder.consistent(.init(text: "版本 2.3 已发布，10 点开会。", context: nil), with: "已发布，点开会。"))
    }

    // MARK: Window titles

    func testWindowTitleIsJournaledMaskedWithTheSentence() {
        recorder.settings.isLearningEnabled = true
        type("看下这个 PR。", in: "chrome", readWindowTitle: { "Pull Request #14 · macos-smart-ime" })
        type("收到。", in: "mail", readWindowTitle: { "收件箱 – alex@example.com" })

        let entries = journalEntries()
        XCTAssertEqual(entries.first { $0.app == "chrome" }?.window, "Pull Request #14 · macos-smart-ime")
        XCTAssertEqual(entries.first { $0.app == "mail" }?.window, "收件箱 – 〔邮箱〕")
        XCTAssertEqual(recorder.windowStats["chrome"]?.found, 1)
    }

    func testSlowWindowTitlesStopWhileFieldReadsContinue() {
        recorder.settings.isLearningEnabled = true
        var titleReads = 0, fieldReads = 0
        let slowTitle = { () -> String? in titleReads += 1; Thread.sleep(forTimeInterval: IntelligenceRecorder.slowRead + 0.05); return "窗口" }
        let field = { () -> String? in fieldReads += 1; return nil }
        type("第一句。", in: "electron", readField: field, readWindowTitle: slowTitle)
        type("第二句。", in: "electron", readField: field, readWindowTitle: slowTitle)

        XCTAssertEqual(titleReads, 1)
        XCTAssertEqual(fieldReads, 2)
        XCTAssertEqual(recorder.windowStats["electron"]?.isStopped, true)
    }

    // MARK: Clearing and settings

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
        XCTAssertFalse(settings.isWindowTitlesEnabled)
        XCTAssertEqual(settings.retentionDays, 30)
        defaults.set(0, forKey: IntelligenceSettings.retentionKey)
        XCTAssertEqual(settings.retentionDays, 1)
        settings.toggleExcluded("mail")
        XCTAssertEqual(settings.excludedApps, ["mail"])
        settings.toggleExcluded("mail")
        XCTAssertEqual(settings.excludedApps, [])
    }

    // MARK: Helpers

    /// Commits a whole sentence (ending in punctuation) as one piece, in its own field.
    private func type(_ sentence: String, in app: String, readField: (() -> String?)? = nil, readWindowTitle: (() -> String?)? = nil) {
        recorder.commit(sentence, app: app, session: sentence.hashValue, secureInput: false, readField: readField, readWindowTitle: readWindowTitle)
        recorder.closeQuietly()
    }

    private func journalEntries() -> [InputJournal.Entry] {
        recorder.journal.flush()
        return recorder.journal.entries(days: 30)
    }

    private func journalTexts() -> [String] {
        journalEntries().map(\.text).reversed()
    }
}
