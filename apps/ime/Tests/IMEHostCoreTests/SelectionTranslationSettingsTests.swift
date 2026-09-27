import AppKit
import XCTest
@testable import IMEHostCore

final class SelectionTranslationSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SelectionTranslationSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreEnabledWithControlOptionT() {
        let settings = SelectionTranslationSettings(defaults: defaults)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertTrue(settings.hotkey.matches(keyCode: 17, modifierFlags: [.control, .option, .capsLock]))
        XCTAssertFalse(settings.hotkey.matches(keyCode: 17, modifierFlags: [.control, .option, .shift]))
    }

    func testCanBeDisabled() {
        defaults.set(false, forKey: SelectionTranslationSettings.enabledKey)

        XCTAssertFalse(SelectionTranslationSettings(defaults: defaults).isEnabled)
    }

    func testCustomHotkey() {
        defaults.set("cmd+shift+y", forKey: SelectionTranslationSettings.hotkeyKey)
        let hotkey = SelectionTranslationSettings(defaults: defaults).hotkey

        XCTAssertTrue(hotkey.matches(keyCode: 16, modifierFlags: [.command, .shift]))
        XCTAssertFalse(hotkey.matches(keyCode: 17, modifierFlags: [.control, .option]))
    }

    func testAliasesAndSpacing() {
        XCTAssertEqual(TranslationHotkey(string: "Control + Alt + T"), .default)
        XCTAssertEqual(TranslationHotkey(string: "command+k"), TranslationHotkey(keyCode: 40, modifiers: [.command]))
    }

    func testInvalidHotkeysFallBackToDefault() {
        for value in ["shift+t", "ctrl+option+tt", "ctrl+option+1", "t", "hyper+t", ""] {
            defaults.set(value, forKey: SelectionTranslationSettings.hotkeyKey)
            XCTAssertEqual(SelectionTranslationSettings(defaults: defaults).hotkey, .default, value)
        }
    }
}
