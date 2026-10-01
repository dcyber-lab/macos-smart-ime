import AppKit
import XCTest
@testable import IMEHostCore

final class CandidateKeyTests: XCTestCase {
    private let one: UInt16 = 18
    private let nine: UInt16 = 25

    func testNumberKeysPickCandidates() {
        XCTAssertEqual(IMEInputController.candidateIndex(forKeyCode: one, modifierFlags: []), 0)
        XCTAssertEqual(IMEInputController.candidateIndex(forKeyCode: nine, modifierFlags: []), 8)
        XCTAssertEqual(IMEInputController.candidateIndex(forKeyCode: one, modifierFlags: .capsLock), 0)
    }

    func testShiftedNumberKeysAreSymbols() {
        XCTAssertNil(IMEInputController.candidateIndex(forKeyCode: one, modifierFlags: .shift))
        XCTAssertNil(IMEInputController.candidateIndex(forKeyCode: one, modifierFlags: .command))
        XCTAssertNil(IMEInputController.candidateIndex(forKeyCode: one, modifierFlags: .option))
    }

    func testOtherKeysPickNothing() {
        XCTAssertNil(IMEInputController.candidateIndex(forKeyCode: 24, modifierFlags: []))
    }
}
