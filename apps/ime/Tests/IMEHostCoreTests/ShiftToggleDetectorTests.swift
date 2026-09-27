import AppKit
import XCTest
@testable import IMEHostCore

final class ShiftToggleDetectorTests: XCTestCase {
    func testStandaloneShiftTapToggles() {
        var detector = ShiftToggleDetector()

        XCTAssertFalse(detector.flagsChanged(.shift))
        XCTAssertTrue(detector.flagsChanged([]))
    }

    func testShiftUsedForCapitalLetterDoesNotToggle() {
        var detector = ShiftToggleDetector()

        XCTAssertFalse(detector.flagsChanged(.shift))
        detector.keyDown()
        XCTAssertFalse(detector.flagsChanged([]))
    }

    func testShortcutWithShiftDoesNotToggle() {
        var detector = ShiftToggleDetector()

        XCTAssertFalse(detector.flagsChanged(.command))
        XCTAssertFalse(detector.flagsChanged([.command, .shift]))
        XCTAssertFalse(detector.flagsChanged(.command))
        XCTAssertFalse(detector.flagsChanged([]))
    }

    func testShiftThenAnotherModifierDoesNotToggle() {
        var detector = ShiftToggleDetector()

        XCTAssertFalse(detector.flagsChanged(.shift))
        XCTAssertFalse(detector.flagsChanged([.shift, .command]))
        XCTAssertFalse(detector.flagsChanged(.shift))
        XCTAssertFalse(detector.flagsChanged([]))
    }

    func testCapsLockDoesNotBlockToggle() {
        var detector = ShiftToggleDetector()

        XCTAssertFalse(detector.flagsChanged([.capsLock, .shift]))
        XCTAssertTrue(detector.flagsChanged(.capsLock))
    }

    func testReleasingOtherModifierDoesNotToggle() {
        var detector = ShiftToggleDetector()

        XCTAssertFalse(detector.flagsChanged(.option))
        XCTAssertFalse(detector.flagsChanged([]))
    }

    func testConsecutiveTapsEachToggle() {
        var detector = ShiftToggleDetector()

        XCTAssertFalse(detector.flagsChanged(.shift))
        XCTAssertTrue(detector.flagsChanged([]))
        XCTAssertFalse(detector.flagsChanged(.shift))
        XCTAssertTrue(detector.flagsChanged([]))
    }
}
