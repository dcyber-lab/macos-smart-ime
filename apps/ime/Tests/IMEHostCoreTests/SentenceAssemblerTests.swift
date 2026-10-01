import XCTest
@testable import IMEHostCore

final class SentenceAssemblerTests: XCTestCase {
    private var sentences: [SentenceAssembler.Sentence] = []
    private var assembler: SentenceAssembler!
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    override func setUp() {
        super.setUp()
        sentences = []
        assembler = SentenceAssembler()
        assembler.onSentence = { [unowned self] in sentences.append($0) }
    }

    func testCommitsJoinUntilSentencePunctuation() {
        assembler.commit("这个功能", app: "slack", at: start)
        assembler.commit("下周上线", app: "slack", at: start + 1)
        XCTAssertTrue(sentences.isEmpty)

        assembler.commit("。", app: "slack", at: start + 2)

        XCTAssertEqual(sentences, [.init(text: "这个功能下周上线。", app: "slack")])
    }

    func testEnglishWordsKeepTheirSpaces() {
        for (i, word) in ["Please ", "review ", "it", "."].enumerated() {
            assembler.commit(word, app: "github", at: start + Double(i))
        }
        XCTAssertEqual(sentences.map(\.text), ["Please review it."])
    }

    func testPauseSwitchAndReturnEndSentences() {
        assembler.commit("第一段", app: "slack", at: start)
        assembler.commit("第二段", app: "slack", at: start + SentenceAssembler.pause + 1)
        assembler.commit("别的应用", app: "mail", at: start + 12)
        assembler.endSentence()

        XCTAssertEqual(sentences.map(\.text), ["第一段", "第二段", "别的应用"])
        XCTAssertEqual(sentences.map(\.app), ["slack", "slack", "mail"])
    }

    func testAnotherSessionStartsANewSentence() {
        assembler.commit("第一个框", app: "notes", session: 1, at: start)
        assembler.commit("第二个框", app: "notes", session: 2, at: start + 1)
        assembler.endSentence()
        XCTAssertEqual(sentences.map(\.text), ["第一个框", "第二个框"])
    }

    func testNewlineSplitsACommit() {
        assembler.commit("上一句\n下一句", app: "notes", at: start)
        assembler.endSentence()
        XCTAssertEqual(sentences.map(\.text), ["上一句", "下一句"])
    }

    func testRecentSentencesAreBoundedPerApp() {
        for i in 0..<8 {
            assembler.commit("第\(i)句。", app: "slack", at: start + Double(i))
        }
        XCTAssertEqual(assembler.recent["slack"], (3..<8).map { "第\($0)句。" })
        assembler.forgetRecent()
        XCTAssertTrue(assembler.recent.isEmpty)
    }
}
