import XCTest
@testable import EnglishEngine

final class PinyinSyllableSegmenterTests: XCTestCase {
    func testPinyinInputIsSegmentable() {
        for input in ["women", "change", "nihao", "shujuku", "zhongguo", "xiang", "lue"] {
            XCTAssertTrue(PinyinSyllableSegmenter.canSegment(input), input)
        }
    }

    func testEnglishInputIsNotSegmentable() {
        for input in ["hello", "deploy", "github", "feature", "the", "commit"] {
            XCTAssertFalse(PinyinSyllableSegmenter.canSegment(input), input)
        }
    }

    func testEmptyAndAbbreviatedInputIsNotSegmentable() {
        XCTAssertFalse(PinyinSyllableSegmenter.canSegment(""))
        XCTAssertFalse(PinyinSyllableSegmenter.canSegment("sjk"))
        XCTAssertFalse(PinyinSyllableSegmenter.canSegment("xx"))
    }
}
