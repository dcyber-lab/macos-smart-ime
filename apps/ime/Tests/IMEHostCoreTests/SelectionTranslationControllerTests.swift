import Foundation
import XCTest
@testable import IMEHostCore

@MainActor
final class SelectionTranslationControllerTests: XCTestCase {
    private let range = NSRange(location: 4, length: 33)
    private var translator: FakeTranslator!
    private var presented: [SelectionTranslationController.State] = []
    private var controller: SelectionTranslationController!

    override func setUp() async throws {
        translator = FakeTranslator()
        presented = []
        controller = SelectionTranslationController(translator: translator) { [weak self] state in
            self?.presented.append(state)
        }
    }

    func testTranslatesSelectionAndReplacesOnReturn() async {
        controller.start(selectedText: " Please review the deployment plan. ", range: range)

        XCTAssertEqual(controller.state, .translating(source: "Please review the deployment plan.", direction: .englishToChinese))
        await waitUntil { if case .result = self.controller.state { true } else { false } }
        XCTAssertEqual(controller.state, .result(
            source: "Please review the deployment plan.", translation: "请审阅部署计划。", direction: .englishToChinese
        ))
        XCTAssertEqual(translator.directions, [.englishToChinese])

        XCTAssertEqual(controller.handleKey(36), .replace("请审阅部署计划。", range))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(presented.last, .idle)
    }

    func testChineseSelectionIsTranslatedToEnglish() async {
        translator.result = .success("Please review the deployment plan before Friday.")
        controller.start(selectedText: "请在周五前审阅部署计划", range: range)

        await waitUntil { if case .result = self.controller.state { true } else { false } }
        XCTAssertEqual(translator.directions, [.chineseToEnglish])
        XCTAssertEqual(controller.handleKey(36), .replace("Please review the deployment plan before Friday.", range))
    }

    func testEscapeDismissesWithoutReplacing() async {
        controller.start(selectedText: "Hello", range: range)
        await waitUntil { if case .result = self.controller.state { true } else { false } }

        XCTAssertEqual(controller.handleKey(53), .dismissed(consumed: true))
        XCTAssertEqual(controller.state, .idle)
    }

    func testOtherKeyDismissesAndIsHandledNormally() async {
        controller.start(selectedText: "Hello", range: range)
        await waitUntil { if case .result = self.controller.state { true } else { false } }

        XCTAssertEqual(controller.handleKey(0), .dismissed(consumed: false))
    }

    func testReturnWhileTranslatingOnlyDismisses() {
        translator.holds = true
        controller.start(selectedText: "Hello", range: range)

        XCTAssertEqual(controller.handleKey(36), .dismissed(consumed: true))
        XCTAssertEqual(controller.state, .idle)
    }

    func testLateResultAfterDismissIsDiscarded() async {
        translator.holds = true
        controller.start(selectedText: "Hello", range: range)
        await waitUntil { self.translator.isWaiting }

        controller.dismiss()
        translator.release()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(presented.contains { if case .result = $0 { true } else { false } })
    }

    func testMessagesForMissingSelection() {
        controller.start(selectedText: nil, range: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(controller.state, .message("当前应用没有提供选中的文字"))

        controller.start(selectedText: "  ", range: range)
        XCTAssertEqual(controller.state, .message("请先选中要翻译的英文"))
    }

    func testMessageWhenModelIsMissing() async {
        translator.result = .failure(SelectionTranslationError.modelNotInstalled(.englishToChinese))
        controller.start(selectedText: "Hello", range: range)

        await waitUntil { if case .message = self.controller.state { true } else { false } }
        guard case .message(let text) = controller.state else {
            return XCTFail("expected a message")
        }
        XCTAssertTrue(text.contains("翻译语言") && text.contains("英语和简体中文"), text)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private final class FakeTranslator: SelectionTranslator, @unchecked Sendable {
    var result: Result<String, Error> = .success("请审阅部署计划。")
    var holds = false
    private(set) var isWaiting = false
    private(set) var directions: [TranslationDirection] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        directions.append(direction)
        if holds {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.isWaiting = true
            }
        }
        return try result.get()
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
