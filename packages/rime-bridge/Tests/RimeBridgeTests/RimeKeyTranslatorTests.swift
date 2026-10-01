import AppKit
import XCTest
@testable import RimeBridge
import SharedModels

final class RimeKeyTranslatorTests: XCTestCase {
    private let shift: Int32 = 1 << 0
    private let control: Int32 = 1 << 2
    private let alt: Int32 = 1 << 3

    func testShiftedSymbolUsesTypedCharacter() {
        // As InputMethodKit delivers Shift+=: the unshifted key in charactersIgnoringModifiers.
        assertKey(keyCode: 24, characters: "+", ignoringModifiers: "=", flags: .shift, is: "+", mask: shift)
        assertKey(keyCode: 18, characters: "!", ignoringModifiers: "1", flags: .shift, is: "!", mask: shift)
        assertKey(keyCode: 44, characters: "?", ignoringModifiers: "/", flags: .shift, is: "?", mask: shift)
    }

    func testUnshiftedSymbol() {
        assertKey(keyCode: 24, characters: "=", ignoringModifiers: "=", flags: [], is: "=", mask: 0)
    }

    func testShiftedLetterIsUppercase() {
        // As InputMethodKit delivers Shift+a: the lowercase key in charactersIgnoringModifiers.
        assertKey(keyCode: 0, characters: "A", ignoringModifiers: "a", flags: .shift, is: "A", mask: shift)
        assertKey(keyCode: 0, characters: "A", ignoringModifiers: "A", flags: .shift, is: "A", mask: shift)
    }

    func testControlShiftBindingUsesKeyLetter() {
        assertKey(keyCode: 35, characters: "\u{10}", ignoringModifiers: "p", flags: [.control, .shift], is: "p", mask: shift | control)
    }

    func testCapsLockKeepsPinyinLowercase() {
        assertKey(keyCode: 0, characters: "A", ignoringModifiers: "a", flags: .capsLock, is: "a", mask: 0)
    }

    func testControlBindingUsesKeyLetter() {
        assertKey(keyCode: 35, characters: "\u{10}", ignoringModifiers: "p", flags: .control, is: "p", mask: control)
    }

    func testOptionSymbolIsNotReplacedByTypedCharacter() {
        assertKey(keyCode: 24, characters: "≠", ignoringModifiers: "=", flags: .option, is: "=", mask: alt)
    }

    func testSpaceWithoutCharacters() {
        assertKey(keyCode: 49, characters: "", ignoringModifiers: "", flags: [], is: " ", mask: 0)
    }

    private func assertKey(
        keyCode: UInt16,
        characters: String,
        ignoringModifiers: String,
        flags: NSEvent.ModifierFlags,
        is expected: Unicode.Scalar,
        mask: Int32,
        line: UInt = #line
    ) {
        let event = InputKeyEvent(
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: ignoringModifiers,
            modifierFlags: flags.rawValue
        )
        let key = RimeKeyTranslator.translate(event)

        XCTAssertEqual(key?.keycode, Int32(expected.value), line: line)
        XCTAssertEqual(key?.mask, mask, line: line)
    }
}
