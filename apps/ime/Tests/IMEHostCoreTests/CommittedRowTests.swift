import AppKit
import XCTest
@testable import IMEHostCore
import SharedModels

final class CommittedRowTests: XCTestCase {
    private let nihao = ["你好", "拟好", "你号", "你", "尼"]

    func testSpaceCommitsTheHighlightedRow() {
        XCTAssertEqual(index(nihao, highlighted: 0, committed: "你好"), 0)
    }

    func testNumberKeyCommitsAnotherRow() {
        XCTAssertEqual(index(nihao, highlighted: 0, committed: "你号"), 2)
    }

    func testPunctuationMatchesTheLongestRowNotASingleCharacter() {
        XCTAssertEqual(index(nihao, highlighted: 3, committed: "你好，"), 0)
    }

    func testEnglishSpaceCommit() {
        let rows = ["deplo", "deploy", "deployment"]

        XCTAssertEqual(index(rows, highlighted: 1, committed: "deploy "), 1)
        XCTAssertEqual(index(rows, highlighted: 1, committed: "deplo "), 0)
    }

    func testRawPinyinMatchesNothing() {
        XCTAssertNil(index(nihao, highlighted: 0, committed: "nihao"))
    }

    func testHighlightingAndVacating() {
        let rows = CandidatePanelModel.rows(for: state(nihao, highlighted: 0))

        XCTAssertEqual(CandidatePanelModel.highlighting(rows, at: 2).map(\.isHighlighted), [false, false, true, false, false])
        let vacated = CandidatePanelModel.vacating(rows, at: 2)
        XCTAssertEqual(vacated.map(\.text), ["你好", "拟好", "", "你", "尼"])
        XCTAssertEqual(vacated.count, rows.count, "the panel keeps its size while it fades")
    }

    @MainActor
    func testRowSnapshotMatchesTheRowAndSeparatesText() throws {
        let view = CandidateListView()
        view.rows = CandidatePanelModel.rows(for: state(nihao, highlighted: 0))
        view.frame = CGRect(origin: .zero, size: view.fittingSize)

        let snapshot = try XCTUnwrap(view.snapshotRow(at: 0))

        XCTAssertEqual(snapshot.size, view.rowRects()[0].size)
        XCTAssertNil(view.snapshotRow(at: nihao.count))
        let edge = CGPoint(x: snapshot.size.width - 2, y: snapshot.size.height / 2)
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.color(at: edge)).alphaComponent, 0.9, "the highlight fill is opaque")
        XCTAssertFalse(snapshot.isText(at: edge), "the text-only snapshot has no fill")
        let midline = (0..<Int(snapshot.size.width)).map { CGPoint(x: CGFloat($0), y: snapshot.size.height / 2) }
        XCTAssertTrue(midline.contains { snapshot.isText(at: $0) }, "the text is in the text-only snapshot")
    }

    private func index(_ texts: [String], highlighted: Int, committed: String) -> Int? {
        CandidatePanelModel.committedRowIndex(in: CandidatePanelModel.rows(for: state(texts, highlighted: highlighted)), committedText: committed)
    }

    private func state(_ texts: [String], highlighted: Int) -> CompositionState {
        CompositionState(
            mode: .chinese,
            compositionText: "x",
            candidates: texts.map { Candidate(text: $0, source: .rime) },
            selectedCandidateIndex: highlighted
        )
    }
}
