import AppKit
@preconcurrency import InputMethodKit
import XCTest
@testable import IMEHostCore

final class CommitEffectMenuTests: XCTestCase {
    private let motionAction = #selector(NSObject.description)
    private let paletteAction = #selector(NSObject.isProxy)

    func testMenuIsFlatWithDisabledSectionTitles() {
        let items = menuItems()

        XCTAssertTrue(items.allSatisfy { $0.submenu == nil }, "submenu actions are not delivered by the input menu")
        let titles = items.filter { !$0.isSeparatorItem && !$0.isEnabled }.map(\.title)
        XCTAssertEqual(titles, [CommitEffectMenu.motionTitle, CommitEffectMenu.paletteTitle])
        XCTAssertEqual(items.filter { $0.action == motionAction }.map(\.title), ["玻璃炸裂", "碎裂下坠", "粒子消散", "随机", "关闭"])
        XCTAssertEqual(items.filter { $0.action == paletteAction }.map(\.title), ["彩虹", "霓虹", "马卡龙", "跟随强调色", "随机"])
    }

    func testCurrentChoicesAreChecked() {
        let checked = menuItems(motion: .off, palette: .random).filter { $0.state == .on }

        XCTAssertEqual(checked.map(\.title), ["关闭", "随机"])
        XCTAssertEqual(checked.map(\.action), [motionAction, paletteAction])
    }

    func testChoicesComeBackFromTheCommandDictionary() {
        let items = menuItems()
        for (index, item) in items.filter({ $0.action == motionAction }).enumerated() {
            XCTAssertEqual(CommitEffectMenu.motionChoice(from: [kIMKCommandMenuItemName: item]), CommitEffectMotionChoice.allChoices[index])
        }
        for (index, item) in items.filter({ $0.action == paletteAction }).enumerated() {
            XCTAssertEqual(CommitEffectMenu.paletteChoice(from: [kIMKCommandMenuItemName: item]), CommitEffectPaletteChoice.allChoices[index])
        }
    }

    func testTitleIsTheFallbackWhenTheTagIsLost() {
        let copy = NSMenuItem(title: "粒子消散", action: nil, keyEquivalent: "")

        XCTAssertEqual(CommitEffectMenu.motionChoice(from: [kIMKCommandMenuItemName: copy]), .style(.dust))
        XCTAssertEqual(CommitEffectMenu.motionChoice(from: copy), .style(.dust))
        XCTAssertNil(CommitEffectMenu.motionChoice(from: ["other": copy]))
        XCTAssertNil(CommitEffectMenu.paletteChoice(from: NSMenuItem(title: "关闭", action: nil, keyEquivalent: "")))
    }

    private func menuItems(motion: CommitEffectMotionChoice = .style(.shatter), palette: CommitEffectPaletteChoice = .palette(.rainbow)) -> [NSMenuItem] {
        CommitEffectMenu.items(motion: motion, palette: palette, motionAction: motionAction, paletteAction: paletteAction)
    }
}
