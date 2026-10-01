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
            appName: { $0 == "slack" ? "Slack" : $0 },
            generatedAt: now
        ))
    }
}
