import XCTest
@testable import EnglishEngine

final class EnglishGlossaryTests: XCTestCase {
    func testParsesTabSeparatedLines() {
        let glossary = EnglishGlossary(tsv: "deploy\t部署\nbroken line\nmeeting\t会议，会面\n")

        XCTAssertEqual(glossary.count, 2)
        XCTAssertEqual(glossary.gloss(for: "meeting"), "会议，会面")
        XCTAssertEqual(glossary.gloss(for: "DEPLOY"), "部署", "lookup is case-insensitive")
    }

    func testBundledGlossesUseWorkplaceMeanings() {
        let glossary = EnglishGlossary.bundled

        XCTAssertEqual(glossary.gloss(for: "deploy"), "部署")
        XCTAssertEqual(glossary.gloss(for: "deploying"), "部署", "inflections of supplement terms share the gloss")
        XCTAssertEqual(glossary.gloss(for: "GitHub"), "代码托管平台")
        XCTAssertEqual(glossary.gloss(for: "roadmap"), "路线图")
        XCTAssertEqual(glossary.gloss(for: "negotiable"), "可磋商的，可转让的")
    }

    func testMostCommonWordsAreNotGlossed() {
        XCTAssertNil(EnglishGlossary.bundled.gloss(for: "the"))
        XCTAssertNil(EnglishGlossary.bundled.gloss(for: "good"))
    }

    func testBundledTableLoadsQuickly() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "en-zh", withExtension: "tsv"))
        let content = try String(contentsOf: url, encoding: .utf8)

        let start = Date()
        let glossary = EnglishGlossary(tsv: content)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(glossary.count, 60_000)
        // Generous bound for unoptimized test builds; release builds are several times faster.
        XCTAssertLessThan(elapsed, 1.0, "parsing took \(elapsed)s")
    }
}
