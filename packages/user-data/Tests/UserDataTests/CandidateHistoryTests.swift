import XCTest
import UserData

final class CandidateHistoryTests: XCTestCase {
    private var clock: TestClock!
    private var history: CandidateHistory!

    override func setUp() {
        super.setUp()
        clock = TestClock()
        history = makeHistory()
    }

    // MARK: Words

    func testWordsAreOrderedByUse() {
        record(words: ["deploy", "deployment", "deployment", "delta"])

        XCTAssertEqual(history.words(withPrefix: "dep", limit: 9), ["deployment", "deploy"])
        XCTAssertEqual(history.words(withPrefix: "dep", limit: 1), ["deployment"])
        XCTAssertEqual(history.words(withPrefix: "x", limit: 9), [])
    }

    func testRecentUseOutweighsOldUse() {
        record(words: ["deploy", "deploy", "deploy"])
        clock.advance(days: 90) // three half-lives: 3 uses now count 0.375
        record(words: ["deployment"])

        XCTAssertEqual(history.words(withPrefix: "dep", limit: 9), ["deployment", "deploy"])
    }

    func testWordsAreBounded() {
        for index in 0...CandidateHistory.maxWords {
            history.recordWord("w\(index)")
        }

        XCTAssertEqual(history.words(withPrefix: "w", limit: .max).count, CandidateHistory.maxWords * 9 / 10)
    }

    // MARK: Choices

    func testChoicesCountEnglishAndChinese() {
        history.recordChoice(input: "gith", english: "GitHub")
        history.recordChoice(input: "gith", english: "GitHub")
        history.recordChoice(input: "gith", english: "git")
        history.recordChoice(input: "gith", english: nil)

        let choices = history.choices(for: "gith")

        XCTAssertEqual(choices.english.map(\.text), ["GitHub", "git"])
        XCTAssertEqual(choices.english.first?.count, 2)
        XCTAssertEqual(choices.score(of: "GitHub"), 2, accuracy: 0.001)
        XCTAssertEqual(choices.chinese, 1, accuracy: 0.001)
        XCTAssertEqual(choices.score(of: "gitlab"), 0)
    }

    func testUnknownInputHasNoChoices() {
        XCTAssertEqual(history.choices(for: "nihao"), .empty)
    }

    func testChoiceScoresDecay() {
        history.recordChoice(input: "gith", english: "GitHub")
        clock.advance(days: 30)

        XCTAssertEqual(history.choices(for: "gith").score(of: "GitHub"), 0.5, accuracy: 0.001)
        XCTAssertEqual(history.choices(for: "gith").english.first?.count, 1)
    }

    // MARK: Persistence

    func testFlushedHistoryLoadsAgain() throws {
        let url = try temporaryFile()
        let saved = makeHistory(fileURL: url)
        saved.recordWord("deploy")
        saved.recordChoice(input: "shujuku", english: "database")
        saved.recordChoice(input: "shujuku", english: nil)
        saved.flush()

        let loaded = makeHistory(fileURL: url)

        XCTAssertEqual(loaded.words(withPrefix: "de", limit: 9), ["deploy"])
        XCTAssertEqual(loaded.choices(for: "shujuku"), saved.choices(for: "shujuku"))
    }

    func testCorruptFileStartsEmptyAndIsReplaced() throws {
        let url = try temporaryFile()
        try Data("not json".utf8).write(to: url)

        let history = makeHistory(fileURL: url)
        XCTAssertEqual(history.words(withPrefix: "d", limit: 9), [])

        history.recordWord("deploy")
        history.flush()
        XCTAssertEqual(makeHistory(fileURL: url).words(withPrefix: "d", limit: 9), ["deploy"])
    }

    func testMissingFileStartsEmpty() throws {
        let history = makeHistory(fileURL: try temporaryFile())

        XCTAssertEqual(history.choices(for: "gith"), .empty)
    }

    // MARK: Helpers

    private func makeHistory(fileURL: URL? = nil) -> CandidateHistory {
        let clock = self.clock!
        return CandidateHistory(fileURL: fileURL, clock: { clock.date })
    }

    private func record(words: [String]) {
        for word in words {
            history.recordWord(word)
        }
    }

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CandidateHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("candidate-history.json")
    }
}

private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func advance(days: Double) {
        date += days * 24 * 60 * 60
    }
}

final class CandidateHistoryClearTests: XCTestCase {
    func testClearForgetsAndDeletesTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CandidateHistoryClear-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let history = CandidateHistory(fileURL: url)
        history.recordWord("github")
        history.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        history.clear()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(history.words(withPrefix: "git", limit: 5), [])
    }
}
