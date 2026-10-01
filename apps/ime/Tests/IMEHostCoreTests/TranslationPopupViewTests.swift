import AppKit
import XCTest
@testable import IMEHostCore

@MainActor
final class TranslationPopupViewTests: XCTestCase {
    /// Labels draw 2 pt inside their frame, so a 14 pt inset leaves at least 12 pt between frame and edge.
    private let minimumGap: CGFloat = 12

    func testLongSourceLineKeepsTheRightInset() {
        let view = laidOut(.result(
            source: "please review the plan before Friday",
            translation: "请在周五前审阅这份计划",
            direction: .englishToChinese
        ))

        assertInsideInsets(view)
    }

    func testMessageWrapsInsideTheInsets() {
        let view = laidOut(.message("未安装英语和简体中文翻译语言，请在“系统设置 › 通用 › 语言与地区 › 翻译语言”中下载。"))

        assertInsideInsets(view)
        XCTAssertLessThan(view.bounds.width, 460, "long messages wrap instead of widening the popup")
        let lineHeight = NSFont.systemFont(ofSize: 16).boundingRectForFont.height
        XCTAssertGreaterThan(leafViews(of: view).map(\.frame.height).max() ?? 0, lineHeight, "the message takes more than one line")
    }

    func testIdleShowsNothing() {
        XCTAssertFalse(TranslationPopupView().configure(for: .idle))
    }

    private func laidOut(_ state: SelectionTranslationController.State) -> TranslationPopupView {
        let view = TranslationPopupView()
        XCTAssertTrue(view.configure(for: state))
        view.frame = CGRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func assertInsideInsets(_ view: NSView, file: StaticString = #filePath, line: UInt = #line) {
        let leaves = leafViews(of: view)
        XCTAssertFalse(leaves.isEmpty, file: file, line: line)
        for leaf in leaves {
            let frame = leaf.convert(leaf.bounds, to: view)
            XCTAssertGreaterThanOrEqual(frame.minX, minimumGap, "\(leaf)", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, view.bounds.width - minimumGap, "\(leaf)", file: file, line: line)
        }
    }

    /// The labels and badge, wherever they sit in the hierarchy.
    private func leafViews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { $0.subviews.isEmpty ? [$0] : leafViews(of: $0) }
    }
}
