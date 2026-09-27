import AppKit
import XCTest
@testable import IMEHostCore
import SharedModels

@MainActor
final class CandidateListViewTests: XCTestCase {
    func testHeightGrowsByExactlyOneRowPerCandidate() {
        let one = height(rowCount: 1)
        let rowHeight = height(rowCount: 2) - one

        XCTAssertGreaterThan(rowHeight, 0)
        for count in 3...9 {
            XCTAssertEqual(height(rowCount: count), one + CGFloat(count - 1) * rowHeight, accuracy: 1, "\(count) rows")
        }
    }

    func testPanelShrinksWhenCandidatesAreRemoved() {
        let view = CandidateListView()
        view.rows = rows(count: 6)
        let sixRows = view.fittingSize.height

        view.rows = rows(count: 2)

        XCTAssertLessThan(view.fittingSize.height, sixRows)
        XCTAssertEqual(view.fittingSize.height, height(rowCount: 2))
    }

    func testWidthFollowsLongestCandidate() {
        let view = CandidateListView()
        view.rows = CandidatePanelModel.rows(for: state(["一", "二"]))
        let short = view.fittingSize.width

        view.rows = CandidatePanelModel.rows(for: state(["一", "internationalization"]))

        XCTAssertGreaterThan(view.fittingSize.width, short)
    }

    private func height(rowCount: Int) -> CGFloat {
        let view = CandidateListView()
        view.rows = rows(count: rowCount)
        return view.fittingSize.height
    }

    private func rows(count: Int) -> [CandidatePanelRow] {
        CandidatePanelModel.rows(for: state((1...count).map { "候选\($0)" }))
    }

    private func state(_ texts: [String]) -> CompositionState {
        CompositionState(
            compositionText: "x",
            candidates: texts.map { Candidate(text: $0, source: .rime, score: 0) },
            selectedCandidateIndex: 0
        )
    }
}
