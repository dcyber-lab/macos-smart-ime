import AppKit
import XCTest
@testable import IMEHostCore

final class HotkeySettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "HotkeySettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreDistinct() {
        let hotkeys = HotkeyAction.allCases.map { $0.hotkey(defaults: defaults) }
        XCTAssertEqual(Set(hotkeys.map(\.displayString)).count, HotkeyAction.allCases.count)
    }

    func testStorageStringRoundTrips() {
        for action in HotkeyAction.allCases {
            XCTAssertEqual(TranslationHotkey(string: action.defaultHotkey.storageString), action.defaultHotkey)
        }
        XCTAssertEqual(TranslationHotkey(keyCode: 6, modifiers: [.command, .shift]).storageString, "shift+cmd+z")
    }

    func testRecordedKeyNeedsAModifierAndALetter() {
        XCTAssertNotNil(TranslationHotkey(keyCode: 0, modifierFlags: [.control, .option, .capsLock]))
        XCTAssertNil(TranslationHotkey(keyCode: 0, modifierFlags: []))
        XCTAssertNil(TranslationHotkey(keyCode: 0, modifierFlags: [.shift]))
        XCTAssertNil(TranslationHotkey(keyCode: 36, modifierFlags: [.command]))
    }

    func testSetStoresWhereTheFeatureReads() {
        XCTAssertNil(HotkeyAction.screenshot.set(TranslationHotkey(string: "cmd+shift+x"), defaults: defaults))
        XCTAssertEqual(ScreenshotSettings(defaults: defaults).hotkey.displayString, "⇧⌘X")
        XCTAssertNil(HotkeyAction.translate.set(TranslationHotkey(string: "cmd+shift+y"), defaults: defaults))
        XCTAssertEqual(SelectionTranslationSettings(defaults: defaults).hotkey.displayString, "⇧⌘Y")
    }

    func testTakenHotkeyIsRefused() {
        let taken = HotkeyAction.screenshot.hotkey(defaults: defaults)
        XCTAssertEqual(HotkeyAction.rewrite.set(taken, defaults: defaults), .screenshot)
        XCTAssertEqual(HotkeyAction.rewrite.hotkey(defaults: defaults), HotkeyAction.rewrite.defaultHotkey)
    }

    func testResetRestoresDefaultUnlessTaken() {
        HotkeyAction.rewrite.set(TranslationHotkey(string: "cmd+shift+r"), defaults: defaults)
        XCTAssertNil(HotkeyAction.rewrite.set(nil, defaults: defaults))
        XCTAssertEqual(HotkeyAction.rewrite.hotkey(defaults: defaults), HotkeyAction.rewrite.defaultHotkey)

        // ⌃⌥R is now used by another action, so rewrite cannot go back to it.
        HotkeyAction.rewrite.set(TranslationHotkey(string: "cmd+shift+r"), defaults: defaults)
        HotkeyAction.translate.set(HotkeyAction.rewrite.defaultHotkey, defaults: defaults)
        XCTAssertEqual(HotkeyAction.rewrite.set(nil, defaults: defaults), .translate)
    }
}
