import XCTest
@testable import IMEHostCore

final class CommitEffectSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CommitEffectSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultIsRainbowGlass() {
        let skin = resolve(CommitEffectSettings(defaults: defaults))

        XCTAssertEqual(skin?.style, .shatter)
        XCTAssertEqual(skin?.palette, .rainbow)
    }

    func testReadsWrittenValues() {
        defaults.set("dust", forKey: CommitEffectSettings.motionKey)
        defaults.set("neon", forKey: CommitEffectSettings.paletteKey)

        let skin = resolve(CommitEffectSettings(defaults: defaults))

        XCTAssertEqual(skin?.style, .dust)
        XCTAssertEqual(skin?.palette, .neon)
    }

    func testUnknownValuesFallBackToDefaults() {
        defaults.set("fireworks", forKey: CommitEffectSettings.motionKey)
        defaults.set("plaid", forKey: CommitEffectSettings.paletteKey)
        let settings = CommitEffectSettings(defaults: defaults)

        XCTAssertEqual(settings.motion, CommitEffectSettings.defaultMotion)
        XCTAssertEqual(settings.palette, CommitEffectSettings.defaultPalette)
    }

    func testOffAndReduceMotionPlayNothing() {
        let settings = CommitEffectSettings(defaults: defaults)

        XCTAssertNil(resolve(settings, reduceMotion: true))
        settings.motion = .off
        XCTAssertNil(resolve(settings))
    }

    func testRandomPicksAgainForEveryCommit() {
        let settings = CommitEffectSettings(defaults: defaults)
        settings.motion = .random
        settings.palette = .random
        var generator = SeededGenerator(seed: 3)

        let skins = (0..<60).compactMap { _ in settings.resolve(reduceMotion: false, using: &generator) }

        XCTAssertEqual(Set(skins.map(\.style)), Set(CommitEffectStyle.allCases))
        XCTAssertEqual(Set(skins.map(\.palette)), Set(CommitEffectPalette.allCases))
    }

    func testMenuChoicesRoundTripThroughDefaults() {
        let settings = CommitEffectSettings(defaults: defaults)
        for choice in CommitEffectMotionChoice.allChoices {
            settings.motion = choice
            XCTAssertEqual(CommitEffectSettings(defaults: defaults).motion, choice)
        }
        for choice in CommitEffectPaletteChoice.allChoices {
            settings.palette = choice
            XCTAssertEqual(CommitEffectSettings(defaults: defaults).palette, choice)
        }
        XCTAssertEqual(CommitEffectMotionChoice.allChoices.map(\.title), ["玻璃炸裂", "碎裂下坠", "粒子消散", "随机", "关闭"])
        XCTAssertEqual(CommitEffectPaletteChoice.allChoices.map(\.title), ["彩虹", "霓虹", "马卡龙", "跟随强调色", "随机"])
    }

    private func resolve(_ settings: CommitEffectSettings, reduceMotion: Bool = false) -> (style: CommitEffectStyle, palette: CommitEffectPalette)? {
        var generator = SeededGenerator(seed: 1)
        return settings.resolve(reduceMotion: reduceMotion, using: &generator)
    }
}
