import AppKit
@preconcurrency import InputMethodKit
import XCTest
@testable import IMEHostCore

final class InputMenuTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "InputMenuTests"
    private let action = #selector(NSObject.description)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testOnlyTheEverydaySwitchesAreInTheMenu() {
        let items = menu(app: (id: "com.tinyspeck.slackmacgap", name: "Slack"))

        XCTAssertEqual(items.map(\.title), ["Intelligence Learning", "Don't Learn in Slack", "Enable AI Hints in Slack", "View Learning Data…", "Settings…"])
        XCTAssertTrue(items.allSatisfy { $0.submenu == nil && $0.action == action }, "submenu actions are not delivered by the input menu")
        XCTAssertTrue(items.allSatisfy(\.isEnabled))
        XCTAssertEqual(items.filter { $0.state == .on }.map(\.title), [], "learning and AI hints are off by default")
    }

    func testStatesFollowTheSettings() {
        IntelligenceSettings(defaults: defaults).isLearningEnabled = true
        IntelligenceSettings(defaults: defaults).toggleExcluded("com.tinyspeck.slackmacgap")
        AIAssistSettings(defaults: defaults).toggleChips(in: "com.tinyspeck.slackmacgap")

        let items = menu(app: (id: "com.tinyspeck.slackmacgap", name: "Slack"))

        XCTAssertEqual(items.filter { $0.state == .on }.map(\.title), ["Intelligence Learning", "Don't Learn in Slack", "Enable AI Hints in Slack"])
    }

    func testDefaultExcludedAppIsCheckedButCanBeAllowed() {
        XCTAssertEqual(menu(app: (id: "com.mitchellh.ghostty", name: "Ghostty"))[1].state, .on)

        IntelligenceSettings(defaults: defaults).toggleExcluded("com.mitchellh.ghostty")

        XCTAssertEqual(menu(app: (id: "com.mitchellh.ghostty", name: "Ghostty"))[1].state, .off)
    }

    func testAIHintsCanBeTurnedOnOnlyWithAModelButAlwaysOff() {
        XCTAssertFalse(menu(app: (id: "notes", name: "备忘录"), aiAvailable: false)[2].isEnabled)

        AIAssistSettings(defaults: defaults).toggleChips(in: "notes")

        XCTAssertTrue(menu(app: (id: "notes", name: "备忘录"), aiAvailable: false)[2].isEnabled)
    }

    func testNoAppItemsWithoutAClient() {
        XCTAssertEqual(menu(app: nil).map(\.title), ["Intelligence Learning", "View Learning Data…", "Settings…"])
    }

    func testCommandsComeBackFromTheCommandDictionary() {
        let items = menu(app: (id: "slack", name: "Slack"))

        XCTAssertEqual(items.map { InputMenu.command(from: [kIMKCommandMenuItemName: $0]) }, [.learning, .excludeApp, .aiHints, .viewLearning, .settings])
        XCTAssertNil(InputMenu.command(from: ["other": items[0]]))
    }

    func testTitleIsTheFallbackWhenTheTagIsLost() {
        func command(_ title: String) -> InputMenu.Command? {
            InputMenu.command(from: NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }

        XCTAssertEqual(command("Don't Learn in WeChat"), .excludeApp)
        XCTAssertEqual(command("Enable AI Hints in WeChat"), .aiHints)
        XCTAssertEqual(command("Settings…"), .settings)
        XCTAssertNil(command("Shatter"))
    }

    private func menu(app: (id: String, name: String)?, aiAvailable: Bool = true) -> [NSMenuItem] {
        InputMenu.items(intelligence: IntelligenceSettings(defaults: defaults), ai: AIAssistSettings(defaults: defaults), currentApp: app,
                        aiAvailable: aiAvailable, action: action)
    }
}
