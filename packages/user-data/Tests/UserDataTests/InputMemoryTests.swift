import XCTest
import UserData

final class InputMemoryTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("input-memory.json") }

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("InputMemoryTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testProfilesCountChineseAndEnglishPerApp() {
        let memory = InputMemory()
        memory.record(sentence: "这个功能下周上线。", app: "slack")
        memory.record(sentence: "Please review the deploy plan.", app: "github")

        XCTAssertEqual(memory.profile(for: "slack")?.hanCharacters ?? 0, 8, accuracy: 0.01)
        XCTAssertEqual(memory.profile(for: "slack")?.chineseShare ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(memory.profile(for: "github")?.englishWords ?? 0, 5, accuracy: 0.01)
        XCTAssertNil(memory.profile(for: "mail"))
    }

    func testRepeatedSentencesAreCountedByFingerprint() {
        let memory = InputMemory()
        XCTAssertEqual(memory.record(sentence: "麻烦大家帮忙回归一下", app: "slack"), 1)
        XCTAssertEqual(memory.record(sentence: "麻烦大家帮忙回归一下", app: "lark"), 2)
        XCTAssertNil(memory.record(sentence: "好的", app: "slack"))

        XCTAssertEqual(memory.timesTyped("麻烦大家帮忙回归一下"), 2)
        XCTAssertEqual(memory.summary().fingerprintCount, 1)
    }

    func testFileHoldsNoSentenceTextAndIsPrivate() throws {
        let memory = InputMemory(fileURL: fileURL)
        memory.record(sentence: "这个功能下周上线，麻烦大家帮忙回归一下", app: "slack")
        memory.flush()

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(contents.contains("上线"))
        XCTAssertTrue(contents.contains("slack"))
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testReloadKeepsCountsAndClearDeletesEverything() {
        let memory = InputMemory(fileURL: fileURL)
        memory.record(sentence: "麻烦大家帮忙回归一下", app: "slack")
        memory.flush()

        let reloaded = InputMemory(fileURL: fileURL)
        XCTAssertEqual(reloaded.timesTyped("麻烦大家帮忙回归一下"), 1)

        reloaded.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(reloaded.timesTyped("麻烦大家帮忙回归一下"), 0)
        XCTAssertTrue(reloaded.summary().apps.isEmpty)
    }

    func testNothingRecordedMeansNoFile() {
        InputMemory(fileURL: fileURL).flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
