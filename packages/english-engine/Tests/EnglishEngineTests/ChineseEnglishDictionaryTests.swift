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

        XCTAssertGreaterThan(dictionary.count, 120000)
        XCTAssertEqual(dictionary.translations(for: "数据库").first, "database")
        XCTAssertEqual(dictionary.translations(for: "苹果").first, "apple")
        XCTAssertEqual(dictionary.translations(for: "北京").first?.hasPrefix("Beijing"), true)
        XCTAssertEqual(dictionary.translations(for: "不存在的词"), [])
        // Everyday words keep CC-CEDICT's glosses.
        XCTAssertEqual(dictionary.translations(for: "问题"), ["question", "problem"])
        XCTAssertEqual(dictionary.translations(for: "开心"), ["feel happy", "rejoice"])
    }

    func testBundledDictionaryTranslatesDeveloperTerms() {
        let dictionary = ChineseEnglishDictionary.bundled

        // Hand-written supplement, with the everyday sense second.
        XCTAssertEqual(dictionary.translations(for: "内核空间"), ["kernel space"])
        XCTAssertEqual(dictionary.translations(for: "仓库"), ["repository", "warehouse"])
        // CC-CEDICT's "(computing)" gloss comes first.
        XCTAssertEqual(dictionary.translations(for: "内核"), ["kernel", "core"])
        // ECDICT's [计] sense fills a headword CC-CEDICT lacks.
        XCTAssertEqual(dictionary.translations(for: "源文件"), ["source file"])
    }

    func testBundledTableLoadsQuickly() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "zh-en", withExtension: "tsv"))
        let content = try String(contentsOf: url, encoding: .utf8)

        let start = Date()
        let dictionary = ChineseEnglishDictionary(tsv: content)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(dictionary.count, 120000)
        // Generous bound for unoptimized test builds; release builds are several times faster.
        XCTAssertLessThan(elapsed, 1.0, "parsing took \(elapsed)s")
    }
}
