import XCTest
import UserData

final class TranslationMissesTests: XCTestCase {
    private var clock: MissesClock!
    private var enabled: MissesSwitch!
    private var misses: TranslationMisses!

    override func setUp() {
        super.setUp()
        clock = MissesClock()
        enabled = MissesSwitch()
        misses = makeMisses()
    }

    func testCandidatesNeedTheMinimumCountAndAreOrderedByScore() {
        record(["灰度环境", "灰度环境", "灰度环境", "飞书文档", "飞书文档", "飞书文档", "飞书文档", "张三丰"])

        XCTAssertEqual(misses.candidates(minimumCount: 3, limit: 9).map(\.text), ["飞书文档", "灰度环境"])
        XCTAssertEqual(misses.candidates(minimumCount: 3, limit: 1).map(\.text), ["飞书文档"])
        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9).last?.text, "张三丰")
    }

    func testRecentCommitsOutweighOldOnes() {
        record(["灰度环境", "灰度环境", "灰度环境", "灰度环境"])
        clock.advance(days: 90) // three half-lives: 4 commits now count 0.5
        record(["飞书文档", "飞书文档", "飞书文档"])

        XCTAssertEqual(misses.candidates(minimumCount: 3, limit: 9).map(\.text), ["飞书文档", "灰度环境"])
    }

    func testProcessedWordsAreNotCountedAgain() {
        record(["灰度环境", "灰度环境", "灰度环境"])
        misses.markProcessed("灰度环境")
        record(["灰度环境", "灰度环境", "灰度环境"])

        XCTAssertTrue(misses.isProcessed("灰度环境"))
        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9), [])
    }

    func testForgottenWordsCanBeCountedAgain() {
        record(["灰度环境", "灰度环境", "灰度环境"])
        misses.forget("灰度环境")

        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9), [])
        XCTAssertFalse(misses.isProcessed("灰度环境"))
        record(["灰度环境"])
        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9).map(\.count), [1])
    }

    func testNothingIsRecordedWhileDisabled() {
        enabled.isOn = false
        record(["灰度环境", "灰度环境", "灰度环境"])

        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: 9), [])
    }

    func testWordsAreBounded() {
        for index in 0...TranslationMisses.maxWords {
            misses.record("词\(index)")
        }

        XCTAssertEqual(misses.candidates(minimumCount: 1, limit: .max).count, TranslationMisses.maxWords * 9 / 10)
    }

    func testLastRun() {
        XCTAssertNil(misses.lastRun)
        misses.recordRun()

        XCTAssertEqual(misses.lastRun, clock.date)
    }

    // MARK: Persistence

    func testFlushedRecordLoadsAgain() throws {
        let url = try temporaryFile()
        let saved = makeMisses(fileURL: url)
        record(["灰度环境", "灰度环境", "灰度环境"], into: saved)
        saved.markProcessed("飞书文档")
        saved.recordRun()
        saved.flush()

        let loaded = makeMisses(fileURL: url)

        XCTAssertEqual(loaded.candidates(minimumCount: 3, limit: 9), saved.candidates(minimumCount: 3, limit: 9))
        XCTAssertTrue(loaded.isProcessed("飞书文档"))
        XCTAssertEqual(loaded.lastRun, clock.date)
    }

    func testCorruptFileStartsEmpty() throws {
        let url = try temporaryFile()
        try Data("not json".utf8).write(to: url)

        let loaded = makeMisses(fileURL: url)

        XCTAssertEqual(loaded.candidates(minimumCount: 1, limit: 9), [])
        XCTAssertNil(loaded.lastRun)
    }

    // MARK: Helpers

    private func makeMisses(fileURL: URL? = nil) -> TranslationMisses {
        let clock = self.clock!
        let enabled = self.enabled!
        return TranslationMisses(fileURL: fileURL, clock: { clock.date }, isEnabled: { enabled.isOn })
    }

    private func record(_ words: [String], into store: TranslationMisses? = nil) {
        for word in words {
            (store ?? misses).record(word)
        }
    }

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranslationMissesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("translation-misses.json")
    }
}

private final class MissesClock: @unchecked Sendable {
    var date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func advance(days: Double) {
        date += days * 24 * 60 * 60
    }
}

private final class MissesSwitch: @unchecked Sendable {
    var isOn = true
}
