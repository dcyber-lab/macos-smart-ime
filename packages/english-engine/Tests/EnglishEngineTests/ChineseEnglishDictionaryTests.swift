import XCTest
@testable import EnglishEngine

final class ChineseEnglishDictionaryTests: XCTestCase {
    func testParsesTabSeparatedLines() {
        let dictionary = ChineseEnglishDictionary(tsv: "数据库\tdatabase\n会议\tmeeting\tconference\n坏行\n")

        XCTAssertEqual(dictionary.count, 2)
        XCTAssertEqual(dictionary.translations(for: "会议"), ["meeting", "conference"])
        XCTAssertEqual(dictionary.translations(for: "坏行"), [])
    }

    func testBundledDictionaryTranslatesCommonWords() {
        let dictionary = ChineseEnglishDictionary.bundled

        XCTAssertGreaterThan(dictionary.count, 80000)
        XCTAssertEqual(dictionary.translations(for: "数据库").first, "database")
        XCTAssertEqual(dictionary.translations(for: "苹果").first, "apple")
        XCTAssertEqual(dictionary.translations(for: "北京").first?.hasPrefix("Beijing"), true)
        XCTAssertEqual(dictionary.translations(for: "不存在的词"), [])
    }

    func testBundledTableLoadsQuickly() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "zh-en", withExtension: "tsv"))
        let content = try String(contentsOf: url, encoding: .utf8)

        let start = Date()
        let dictionary = ChineseEnglishDictionary(tsv: content)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(dictionary.count, 80000)
        // Generous bound for unoptimized test builds; release builds are several times faster.
        XCTAssertLessThan(elapsed, 1.0, "parsing took \(elapsed)s")
    }
}
