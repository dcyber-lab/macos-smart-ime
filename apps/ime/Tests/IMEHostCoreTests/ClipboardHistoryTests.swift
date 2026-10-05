import XCTest
@testable import IMEHostCore

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(maxItems: Int = 300, retentionDays: Int = 30) -> ClipboardHistoryStore {
        ClipboardHistoryStore(directory: directory, maxItems: maxItems, retentionDays: retentionDays)
    }

    func testNewestFirstAndRepeatCopyMovesUp() {
        let store = makeStore()
        store.addText("one", app: nil)
        store.addText("two", app: nil)
        store.addText("one", app: nil)
        XCTAssertEqual(store.items.map(\.text), ["one", "two"])
    }

    func testRejectsBlankAndOversizedText() {
        let store = makeStore()
        XCTAssertFalse(store.addText("  \n ", app: nil))
        XCTAssertFalse(store.addText(String(repeating: "a", count: ClipboardHistoryStore.maxTextBytes + 1), app: nil))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testSearchMatchesEveryWordIgnoringCase() {
        let store = makeStore()
        store.addText("sudo /Users/heng/go", app: nil)
        store.addText("mad today $40.96", app: nil)
        XCTAssertEqual(store.search("SUDO go").map(\.text), ["sudo /Users/heng/go"])
        XCTAssertEqual(store.search("").count, 2)
        XCTAssertTrue(store.search("nothing").isEmpty)
    }

    func testPinnedFirstAndSurvivesPrune() {
        let store = makeStore(maxItems: 2)
        let now = Date()
        store.addText("old", app: nil, now: now.addingTimeInterval(-100))
        store.togglePin(store.items[0])
        for text in ["a", "b", "c"] {
            store.addText(text, app: nil, now: now)
        }
        XCTAssertEqual(store.search("").map(\.text), ["old", "c", "b"])
    }

    func testPruneDropsOldEntries() {
        let store = makeStore(retentionDays: 7)
        let now = Date()
        store.addText("stale", app: nil, now: now.addingTimeInterval(-8 * 86_400))
        store.addText("fresh", app: nil, now: now)
        XCTAssertEqual(store.items.map(\.text), ["fresh"])
    }

    func testImagesAreStoredAndRemoved() throws {
        let store = makeStore()
        XCTAssertTrue(store.addImage(png: Data([1, 2, 3]), width: 975, height: 541, app: nil))
        let item = try XCTUnwrap(store.items.first)
        let url = try XCTUnwrap(store.imageURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(item.title.contains("975×541"))
        store.remove(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPersistsAcrossReload() {
        let store = makeStore()
        store.addText("kept", app: "com.apple.Terminal")
        store.togglePin(store.items[0])
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.items.map(\.text), ["kept"])
        XCTAssertTrue(reloaded.isPinned(reloaded.items[0]))
    }

    func testClearKeepsPinned() {
        let store = makeStore()
        store.addText("pinned", app: nil)
        store.togglePin(store.items[0])
        store.addText("loose", app: nil)
        store.clear()
        XCTAssertEqual(store.items.map(\.text), ["pinned"])
    }

    func testTitleIsFirstNonEmptyLine() {
        let store = makeStore()
        store.addText("\n  hello\nworld", app: nil)
        XCTAssertEqual(store.items[0].title, "hello")
    }

    func testSecretsAndPasswordManagersAreNotRecorded() {
        XCTAssertFalse(ClipboardSettings.allowsCopy(from: "com.1password.1password", types: ["public.utf8-plain-text"]))
        XCTAssertFalse(ClipboardSettings.allowsCopy(from: "com.apple.TextEdit", types: ["org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(ClipboardSettings.allowsCopy(from: "com.apple.Terminal", types: ["public.utf8-plain-text"]))
    }
}
