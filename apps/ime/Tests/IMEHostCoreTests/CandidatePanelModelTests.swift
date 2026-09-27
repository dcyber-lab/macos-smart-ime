import CoreGraphics
import XCTest
@testable import IMEHostCore
import SharedModels

final class CandidatePanelModelTests: XCTestCase {
    func testRowsAreNumberedInOrder() {
        let rows = CandidatePanelModel.rows(for: state([("数据库", .rime), ("数据", .rime), ("书局", .rime)]))

        XCTAssertEqual(rows.map(\.label), ["1", "2", "3"])
        XCTAssertEqual(rows.map(\.text), ["数据库", "数据", "书局"])
        XCTAssertEqual(rows.compactMap(\.tag), [])
        XCTAssertFalse(rows.contains { $0.hasSeparatorBefore })
    }

    func testSelectedIndexIsHighlighted() {
        let rows = CandidatePanelModel.rows(for: state([("数据库", .rime), ("数据", .rime)], selected: 1))

        XCTAssertEqual(rows.map(\.isHighlighted), [false, true])
    }

    func testTranslationAfterChineseIsTaggedAndSeparated() {
        let rows = CandidatePanelModel.rows(
            for: state([("数据库", .rime), ("数据", .rime), ("database", .englishTranslation)])
        )

        XCTAssertEqual(rows.map(\.tag), [nil, nil, "译"])
        XCTAssertEqual(rows.map(\.hasSeparatorBefore), [false, false, true])
    }

    func testEnglishWordBeforeChineseIsTaggedAndSeparated() {
        let rows = CandidatePanelModel.rows(
            for: state([("hello", .englishCompletion), ("合理", .rime), ("荷兰", .rime)])
        )

        XCTAssertEqual(rows.map(\.tag), ["英", nil, nil])
        XCTAssertEqual(rows.map(\.hasSeparatorBefore), [false, true, false])
    }

    func testTranslationsAndWordsShareOneEnglishGroup() {
        let rows = CandidatePanelModel.rows(
            for: state([("我们", .rime), ("we", .englishTranslation), ("women", .englishCompletion)])
        )

        XCTAssertEqual(rows.map(\.tag), [nil, "译", "英"])
        XCTAssertEqual(rows.map(\.hasSeparatorBefore), [false, true, false])
    }

    func testEnglishOnlyListHasNoTagsOrSeparators() {
        let rows = CandidatePanelModel.rows(
            for: state([("he", .englishCompletion), ("her", .englishCompletion), ("here", .englishCompletion)])
        )

        XCTAssertEqual(rows.compactMap(\.tag), [])
        XCTAssertFalse(rows.contains { $0.hasSeparatorBefore })
    }

    private func state(_ candidates: [(String, CandidateSource)], selected: Int? = 0) -> CompositionState {
        CompositionState(
            compositionText: "x",
            candidates: candidates.map { Candidate(text: $0.0, source: $0.1, score: 0) },
            selectedCandidateIndex: selected
        )
    }
}

final class CandidatePanelPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 200, height: 180)

    func testPanelSitsBelowCaret() {
        let caret = CGRect(x: 300, y: 600, width: 0, height: 18)

        let origin = CandidatePanelPlacement.origin(panelSize: size, caretRect: caret, visibleFrame: screen)

        XCTAssertEqual(origin, CGPoint(x: 300, y: 600 - CandidatePanelPlacement.caretGap - 180))
    }

    func testPanelFlipsAboveCaretNearScreenBottom() {
        let caret = CGRect(x: 300, y: 100, width: 0, height: 18)

        let origin = CandidatePanelPlacement.origin(panelSize: size, caretRect: caret, visibleFrame: screen)

        XCTAssertEqual(origin.y, 118 + CandidatePanelPlacement.caretGap)
    }

    func testPanelShiftsLeftNearRightEdge() {
        let caret = CGRect(x: 1400, y: 600, width: 0, height: 18)

        let origin = CandidatePanelPlacement.origin(panelSize: size, caretRect: caret, visibleFrame: screen)

        XCTAssertEqual(origin.x, 1440 - 200)
    }

    func testPanelRespectsSecondaryScreenOffset() {
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let caret = CGRect(x: 1500, y: -150, width: 0, height: 18)

        let origin = CandidatePanelPlacement.origin(panelSize: size, caretRect: caret, visibleFrame: secondary)

        XCTAssertEqual(origin, CGPoint(x: 1500, y: -132 + CandidatePanelPlacement.caretGap))
    }

    func testReportedCaretIsUsedWhenValid() {
        let reported = CGRect(x: 10, y: 20, width: 0, height: 18)

        XCTAssertEqual(
            CandidatePanelPlacement.caretRect(reported: reported, lastKnown: nil, mouseLocation: .zero),
            reported
        )
    }

    func testEmptyCaretFallsBackToLastKnownThenMouse() {
        let last = CGRect(x: 50, y: 60, width: 0, height: 18)

        XCTAssertEqual(
            CandidatePanelPlacement.caretRect(reported: .zero, lastKnown: last, mouseLocation: CGPoint(x: 1, y: 2)),
            last
        )
        XCTAssertEqual(
            CandidatePanelPlacement.caretRect(reported: .zero, lastKnown: nil, mouseLocation: CGPoint(x: 1, y: 2)),
            CGRect(x: 1, y: 2, width: 0, height: 0)
        )
    }
}
