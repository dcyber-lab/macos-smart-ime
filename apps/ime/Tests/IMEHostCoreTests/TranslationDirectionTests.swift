import XCTest
@testable import IMEHostCore

final class TranslationDirectionTests: XCTestCase {
    func testEnglishSentence() {
        XCTAssertEqual(TranslationDirection.detect("please review the plan"), .englishToChinese)
    }

    func testChineseSentence() {
        XCTAssertEqual(TranslationDirection.detect("请在周五前审阅部署计划"), .chineseToEnglish)
    }

    func testChineseSentenceWithEnglishTerms() {
        XCTAssertEqual(TranslationDirection.detect("这个feature要deploy到production"), .chineseToEnglish)
        XCTAssertEqual(TranslationDirection.detect("你好meetinghellowomen测试he 数据库GitHub"), .chineseToEnglish)
    }

    func testEnglishSentenceWithChineseTerm() {
        XCTAssertEqual(TranslationDirection.detect("Let's discuss 数据库 design"), .englishToChinese)
        XCTAssertEqual(TranslationDirection.detect("Please use 飞书 for the meeting"), .englishToChinese)
        XCTAssertEqual(TranslationDirection.detect("我在用GitHub"), .chineseToEnglish)
    }

    func testTextWithoutLettersDefaultsToEnglish() {
        XCTAssertEqual(TranslationDirection.detect("2026-09-27 14:00"), .englishToChinese)
        XCTAssertEqual(TranslationDirection.detect(""), .englishToChinese)
    }

    func testLabels() {
        XCTAssertEqual(TranslationDirection.englishToChinese.label, "英 → 中")
        XCTAssertEqual(TranslationDirection.chineseToEnglish.label, "中 → 英")
    }
}
