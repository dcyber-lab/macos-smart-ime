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

    func testShortListsHugTheirContentWidth() {
        let view = CandidateListView()
        view.rows = CandidatePanelModel.rows(for: state(["你"]))
        let oneCharacter = view.fittingSize.width

        view.rows = CandidatePanelModel.rows(for: state(["你好世界"]))

        XCTAssertGreaterThan(view.fittingSize.width, oneCharacter, "no fixed minimum width")
        XCTAssertLessThan(oneCharacter, 80, "a one-character list stays narrow")
    }

    func testAnnotationWidensThePanel() {
        let plain = CandidateListView()
        plain.rows = CandidatePanelModel.rows(for: state(["deploy"]))
        let annotated = CandidateListView()
        annotated.rows = CandidatePanelModel.rows(for: CompositionState(
            compositionText: "x",
            candidates: [Candidate(text: "deploy", source: .englishCompletion, annotation: "部署")],
            selectedCandidateIndex: 0
        ))

        XCTAssertGreaterThan(annotated.fittingSize.width, plain.fittingSize.width)
        XCTAssertEqual(annotated.fittingSize.height, plain.fittingSize.height)
    }

    func testHeaderAddsHeightAndFitsItsText() {
        let view = CandidateListView()
        view.rows = rows(count: 3)
        let withoutHeader = view.fittingSize

        view.header = CandidatePanelHeader(text: "zhong hua ren min gong he guo", canPageUp: true, canPageDown: true)

        XCTAssertGreaterThan(view.fittingSize.height, withoutHeader.height)
        XCTAssertGreaterThan(view.fittingSize.width, withoutHeader.width, "a long preedit widens the panel")
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
            candidates: texts.map { Candidate(text: $0, source: .rime) },
            selectedCandidateIndex: 0
        )
    }
}
