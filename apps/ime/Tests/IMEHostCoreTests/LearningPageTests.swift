import XCTest
@testable import IMEHostCore
import UserData

final class LearningPageTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testJournalEntriesAreEscapedAndSearchable() {
        let html = page(journal: true, entries: [
            .init(time: now, app: "slack", text: "<script>alert(1)</script> & 上线"),
        ])

        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; 上线"))
        XCTAssertTrue(html.contains("id=\"q\""), "has a search box")
        XCTAssertTrue(html.contains("Slack"))
    }

    func testJournalOffSaysSo() {
        let html = page(journal: false, entries: [])

        XCTAssertTrue(html.contains("未保存输入原文"))
        XCTAssertFalse(html.contains("id=\"q\""))
    }

    func testSummaryShowsAppsAndFingerprintsWithoutExternalResources() {
        let memory = InputMemory()
        memory.record(sentence: "这个功能下周上线。", app: "slack")
        let html = page(journal: true, entries: [], summary: memory.summary())

        XCTAssertTrue(html.contains("<td>Slack</td><td>8</td>"))
        XCTAssertTrue(html.contains("1 条"))
        XCTAssertFalse(html.contains("http://") || html.contains("https://"), "no external resources")
    }

    private func page(journal: Bool, entries: [InputJournal.Entry], summary: InputMemory.Summary? = nil) -> String {
        LearningPage.html(.init(
            isLearningEnabled: true,
            isJournalEnabled: journal,
            retentionDays: 30,
            excludedApps: ["终端"],
            summary: summary ?? InputMemory().summary(),
            entries: entries,
            insights: LearningInsights.compute(entries: entries, summary: summary ?? InputMemory().summary()),
            appName: { $0 == "slack" ? "Slack" : $0 },
            generatedAt: now
        ))
    }
}

final class LearningInsightsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    private func entries(_ texts: [String], app: String = "slack") -> [InputJournal.Entry] {
        texts.enumerated().map { .init(time: day + Double($0.offset) * 3_600, app: app, text: $0.element) }
    }

    func testFrequentWordsSkipFunctionWords() {
        let insights = LearningInsights.compute(entries: entries([
            "这个功能下周上线", "上线之前先回归", "回归测试通过就上线", "我们的 Kubernetes 集群", "Kubernetes deploy 报错",
        ]), summary: InputMemory().summary(), calendar: calendar)

        XCTAssertEqual(insights.chineseWords.first, .init(text: "上线", count: 3))
        XCTAssertTrue(insights.chineseWords.contains(.init(text: "回归", count: 2)))
        XCTAssertFalse(insights.chineseWords.contains { $0.text == "这个" || $0.text == "我们" })
        XCTAssertEqual(insights.englishWords.first, .init(text: "Kubernetes", count: 2))
    }

    func testRepeatedSentencesAndNewWords() {
        let insights = LearningInsights.compute(entries: entries([
            "麻烦大家帮忙回归一下", "麻烦大家帮忙回归一下", "麻烦大家帮忙回归一下", "灵译好用", "灵译真快", "打开灵译", "今天开会",
        ]), summary: InputMemory().summary(), calendar: calendar)

        XCTAssertEqual(insights.repeatedSentences, [.init(text: "麻烦大家帮忙回归一下", count: 3)])
        XCTAssertTrue(insights.newWords.contains(.init(text: "灵译", count: 3)), "\(insights.newWords)")
    }

    func testSchedulesNeedATimeOfDay() {
        let insights = LearningInsights.compute(entries: entries([
            "明天下午三点和 Alex 过方案", "今天天气不错", "3点开会", "Let's sync tomorrow at 3pm", "下周再说",
        ]), summary: InputMemory().summary(), calendar: calendar)

        XCTAssertEqual(insights.schedules.map(\.text), ["明天下午三点和 Alex 过方案", "3点开会", "Let's sync tomorrow at 3pm"])
        XCTAssertEqual(insights.schedules[1].mention, "3点")
        // NSDataDetector parses Chinese dates only when Chinese is among the preferred languages (not on
        // CI); English dates parse everywhere.
        XCTAssertNotNil(insights.schedules[2].when)
    }

    func testOverviewAndAppLanguages() {
        let memory = InputMemory()
        memory.record(sentence: String(repeating: "中文句子", count: 10), app: "lark")
        memory.record(sentence: Array(repeating: "english words here", count: 10).joined(separator: " "), app: "github")
        let insights = LearningInsights.compute(entries: entries(["第一句话", "第二句话"]) + entries(["English one"], app: "github"),
                                                summary: memory.summary(), calendar: calendar)

        XCTAssertEqual(insights.sentenceCount, 3)
        XCTAssertEqual(insights.dayCount, 1)
        XCTAssertEqual(insights.topApps.first, .init(text: "slack", count: 2))
        XCTAssertEqual(Set(insights.appLanguages.map(\.language)), [.chinese, .english])
    }

    func testPageShowsInsightsWithTheirNextSteps() {
        let list = entries(["麻烦大家帮忙回归一下", "麻烦大家帮忙回归一下", "明天下午三点开会"])
        let html = LearningPage.html(.init(
            isLearningEnabled: true, isJournalEnabled: true, retentionDays: 30, excludedApps: [],
            summary: InputMemory().summary(), entries: list,
            insights: LearningInsights.compute(entries: list, summary: InputMemory().summary(), calendar: calendar),
            appName: { $0 }, generatedAt: day
        ))

        XCTAssertTrue(html.contains("学到了什么"))
        XCTAssertTrue(html.contains("重复说过的话"))
        XCTAssertTrue(html.contains("存成短语"))
        XCTAssertTrue(html.contains("提到时间的句子"))
    }

    func testComputingAMonthOfTypingIsQuick() {
        let texts = (0..<3_000).map { "第\($0)句：这个功能下周上线，麻烦大家明天下午三点帮忙回归 deploy 一下" }
        let start = CFAbsoluteTimeGetCurrent()
        _ = LearningInsights.compute(entries: entries(texts), summary: InputMemory().summary(), calendar: calendar)
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 3, "runs in the background, but should stay well under a few seconds")
    }
}

final class TimeOfDayTests: XCTestCase {
    func testTimeOfDayMarkers() {
        for text in ["明天下午三点", "后天 14:30 面试", "sync tomorrow at 3pm", "3 PM call", "see you tonight", "两点半"] {
            XCTAssertTrue(LearningInsights.hasTimeOfDay(text), text)
        }
        for text in ["今天天气不错", "第3句：这个功能", "our team uses npm", "下周再说"] {
            XCTAssertFalse(LearningInsights.hasTimeOfDay(text), text)
        }
    }
}

final class LearningSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testSessionsSplitByAppAndGap() {
        let newestFirst: [InputJournal.Entry] = [
            .init(time: t0 + 1_500, app: "ghostty", text: "现在可以装了吗"),
            .init(time: t0 + 1_400, app: "ghostty", text: "我试试"),
            .init(time: t0 + 300, app: "seatalk", text: "还在上班呢？"),
            .init(time: t0 + 0, app: "seatalk", text: "合了"),
            .init(time: t0 - 1_000, app: "seatalk", text: "早上好"),
        ]

        let sessions = LearningPage.sessions(newestFirst)

        XCTAssertEqual(sessions.map { $0.map(\.text) }, [["我试试", "现在可以装了吗"], ["合了", "还在上班呢？"], ["早上好"]])
    }

    func testPageShowsSessionsContextAndReadCost() {
        let entries: [InputJournal.Entry] = [
            .init(time: t0 + 60, app: "notes", text: "下周上线。", context: "发布计划"),
            .init(time: t0, app: "notes", text: "先回归。"),
        ]
        var stats = IntelligenceRecorder.ContextStats()
        stats.reads = 2
        stats.found = 1
        stats.totalSeconds = 0.004
        stats.slowestSeconds = 0.003
        let html = LearningPage.html(.init(
            isLearningEnabled: true, isJournalEnabled: true, retentionDays: 30, excludedApps: [],
            summary: InputMemory().summary(), entries: entries,
            insights: LearningInsights.compute(entries: entries, summary: InputMemory().summary()),
            contextStats: ["notes": stats], appName: { $0 == "notes" ? "备忘录" : $0 }, generatedAt: t0
        ))

        XCTAssertTrue(html.contains("共 2 条，1 段"))
        XCTAssertTrue(html.contains("前文：发布计划"))
        XCTAssertTrue(html.contains("<td>备忘录</td><td>2</td><td>1</td><td>2.0 ms</td><td>3.0 ms</td><td>正常</td>"))
    }
}
