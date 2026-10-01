import XCTest
import UserData

final class InputJournalTests: XCTestCase {
    private var directory: URL!
    private let clock = JournalClock()
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("InputJournalTests-\(UUID().uuidString)/journal")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        super.tearDown()
    }

    private func makeJournal() -> InputJournal {
        InputJournal(directoryURL: directory, clock: { [clock] in clock.now }, calendar: calendar)
    }

    func testEntriesComeBackNewestFirst() {
        let journal = makeJournal()
        journal.append("第一句。", app: "slack")
        clock.now += 60
        journal.append("Second one.", app: "github")
        journal.flush()

        let entries = journal.entries(days: 30)
        XCTAssertEqual(entries.map(\.text), ["Second one.", "第一句。"])
        XCTAssertEqual(entries.map(\.app), ["github", "slack"])
    }

    func testFilesArePrivateAndExcludedFromBackup() throws {
        let journal = makeJournal()
        journal.append("第一句。", app: "slack")
        journal.flush()

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let fileMode = try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(fileMode?.intValue, 0o600)
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testOldDaysArePrunedAndRecentOnesKept() {
        let journal = makeJournal()
        journal.append("很久以前。", app: "slack")
        clock.now += 40 * 86_400
        journal.append("今天。", app: "slack")
        journal.flush()

        journal.prune(keepingDays: 30)
        journal.flush()

        XCTAssertEqual(journal.entries(days: 365).map(\.text), ["今天。"])
    }

    func testClearRemovesTheJournal() {
        let journal = makeJournal()
        journal.append("第一句。", app: "slack")
        journal.flush()

        journal.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(journal.entries(days: 30).isEmpty)
    }
}

private final class JournalClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
}

final class InputJournalContextTests: XCTestCase {
    func testContextRoundTripsAndOldLinesStillRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InputJournalContext-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = InputJournal(directoryURL: directory)
        journal.append("下周上线。", app: "notes", context: "发布计划：")
        journal.flush()
        // A line written before context existed.
        let file = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)[0]
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"t":"2026-10-01T08:00:00Z","app":"slack","text":"旧格式。"}"#.utf8 + [0x0A]))
        try handle.close()

        let entries = journal.entries(days: 30)
        XCTAssertEqual(entries.map(\.text).sorted(), ["下周上线。", "旧格式。"])
        XCTAssertEqual(entries.first { $0.text == "下周上线。" }?.context, "发布计划：")
        XCTAssertNil(entries.first { $0.text == "旧格式。" }?.context)
    }
}
