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

        XCTAssertEqual(items.map(\.title), ["智能中心", "智能学习", "保存输入原文", "读取窗口标题", "不在「Slack」中学习", "查看学习记录…", "清除学习记录…"])
        XCTAssertFalse(items[0].isEnabled)
        XCTAssertEqual(items[1].state, .off)
        XCTAssertFalse(items[2].isEnabled, "the journal only matters while learning is on")
        XCTAssertFalse(items[3].isEnabled)
        XCTAssertEqual(items[3].state, .off, "window titles are off by default")
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
        XCTAssertEqual(items[4].state, .on)
    }

    func testWindowTitlesAskForAccessUntilGranted() {
        let settings = IntelligenceSettings(defaults: defaults)
        settings.isLearningEnabled = true
        settings.isWindowTitlesEnabled = true

        let untrusted = IntelligenceMenu.items(settings: settings, currentApp: nil, isAccessibilityTrusted: false, action: action)[3]
        let trusted = IntelligenceMenu.items(settings: settings, currentApp: nil, isAccessibilityTrusted: true, action: action)[3]

        XCTAssertEqual(untrusted.title, "读取窗口标题（需授权辅助功能）")
        XCTAssertEqual(trusted.title, "读取窗口标题")
        XCTAssertEqual(trusted.state, .on)
        XCTAssertEqual(IntelligenceMenu.command(from: NSMenuItem(title: untrusted.title, action: nil, keyEquivalent: "")), .windowTitles)
    }

    func testDefaultExcludedAppIsCheckedButCanBeAllowed() {
        XCTAssertEqual(menu(app: (id: "com.mitchellh.ghostty", name: "Ghostty"))[4].state, .on)
        XCTAssertTrue(menu(app: (id: "com.mitchellh.ghostty", name: "Ghostty"))[4].isEnabled)

        IntelligenceSettings(defaults: defaults).toggleExcluded("com.mitchellh.ghostty")

        XCTAssertEqual(menu(app: (id: "com.mitchellh.ghostty", name: "Ghostty"))[4].state, .off)
    }

    func testNoAppItemWithoutAClient() {
        XCTAssertFalse(menu(app: nil).contains { $0.title.hasPrefix("不在「") })
    }

    func testCommandsComeBackFromTheCommandDictionary() {
        let items = menu(app: (id: "slack", name: "Slack")).filter { $0.action == action }
        XCTAssertEqual(items.map { IntelligenceMenu.command(from: [kIMKCommandMenuItemName: $0]) }, [.learning, .journal, .windowTitles, .excludeApp, .view, .clear])
        XCTAssertEqual(IntelligenceMenu.command(from: NSMenuItem(title: "不在「微信」中学习", action: nil, keyEquivalent: "")), .excludeApp)
        XCTAssertNil(IntelligenceMenu.command(from: NSMenuItem(title: "玻璃炸裂", action: nil, keyEquivalent: "")))
    }

    private func menu(app: (id: String, name: String)?) -> [NSMenuItem] {
        IntelligenceMenu.items(settings: IntelligenceSettings(defaults: defaults), currentApp: app, action: action)
    }
}
