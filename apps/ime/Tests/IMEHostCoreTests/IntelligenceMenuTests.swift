import AppKit
@preconcurrency import InputMethodKit
import XCTest
@testable import IMEHostCore

final class IntelligenceMenuTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "IntelligenceMenuTests"
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

    func testOffByDefaultWithTheJournalGrayedOut() {
        let items = menu(app: (id: "com.tinyspeck.slackmacgap", name: "Slack"))

        XCTAssertEqual(items.map(\.title), ["智能中心", "智能学习", "保存输入原文", "不在「Slack」中学习", "查看学习记录…", "清除学习记录…"])
        XCTAssertFalse(items[0].isEnabled)
        XCTAssertEqual(items[1].state, .off)
        XCTAssertFalse(items[2].isEnabled, "the journal only matters while learning is on")
        XCTAssertTrue(items.allSatisfy { $0.submenu == nil })
    }

    func testStatesFollowTheSettings() {
        let settings = IntelligenceSettings(defaults: defaults)
        settings.isLearningEnabled = true
        settings.toggleExcluded("com.tinyspeck.slackmacgap")
        let items = menu(app: (id: "com.tinyspeck.slackmacgap", name: "Slack"))

        XCTAssertEqual(items[1].state, .on)
        XCTAssertTrue(items[2].isEnabled)
        XCTAssertEqual(items[2].state, .on)
        XCTAssertEqual(items[3].state, .on)
    }

    func testDefaultExcludedAppIsCheckedAndLocked() {
        let item = menu(app: (id: "com.apple.Terminal", name: "终端"))[3]

        XCTAssertEqual(item.state, .on)
        XCTAssertFalse(item.isEnabled)
    }

    func testNoAppItemWithoutAClient() {
        XCTAssertFalse(menu(app: nil).contains { $0.title.hasPrefix("不在「") })
    }

    func testCommandsComeBackFromTheCommandDictionary() {
        let items = menu(app: (id: "slack", name: "Slack")).filter { $0.action == action }
        XCTAssertEqual(items.map { IntelligenceMenu.command(from: [kIMKCommandMenuItemName: $0]) }, [.learning, .journal, .excludeApp, .view, .clear])
        XCTAssertEqual(IntelligenceMenu.command(from: NSMenuItem(title: "不在「微信」中学习", action: nil, keyEquivalent: "")), .excludeApp)
        XCTAssertNil(IntelligenceMenu.command(from: NSMenuItem(title: "玻璃炸裂", action: nil, keyEquivalent: "")))
    }

    private func menu(app: (id: String, name: String)?) -> [NSMenuItem] {
        IntelligenceMenu.items(settings: IntelligenceSettings(defaults: defaults), currentApp: app, action: action)
    }
}
