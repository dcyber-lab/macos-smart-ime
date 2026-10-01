import AppKit
import XCTest
@testable import IMEHostCore

final class CommitEffectTests: XCTestCase {
    private let row = CGSize(width: 113, height: 31)

    func testSameSeedGivesSameFragments() {
        for style in CommitEffectStyle.allCases {
            let a = effect(style, .rainbow, seed: 42), b = effect(style, .rainbow, seed: 42)
            XCTAssertEqual(a.fragments, b.fragments, "\(style)")
            XCTAssertNotEqual(a.fragments, effect(style, .rainbow, seed: 43).fragments, "\(style)")
        }
    }

    func testShardsTileTheRow() {
        for style in [CommitEffectStyle.shatter, .crumble] {
            let total = effect(style, .accent).fragments.map { area(of: $0.polygon) }.reduce(0, +)
            XCTAssertEqual(total, row.width * row.height, accuracy: 0.5, "\(style)")
        }
    }

    func testDustCoversEveryVisibleCell() {
        let dust = effect(.dust, .accent)
        let cells = Int(ceil(row.width / 3)) * Int(ceil(row.height / 3))

        XCTAssertEqual(dust.fragments.count, cells)
    }

    func testFragmentsStartInPlace() {
        for style in CommitEffectStyle.allCases {
            let effect = effect(style, .rainbow)
            for fragment in effect.fragments {
                XCTAssertEqual(effect.pose(of: fragment, at: 0), CommitEffectPose(offset: .zero, rotation: 0, scale: 1, alpha: 1))
            }
        }
    }

    func testFragmentsMoveAndFade() {
        let effect = effect(.shatter, .rainbow)
        let poses = effect.fragments.compactMap { effect.pose(of: $0, at: effect.crackDuration + 0.2) }

        XCTAssertFalse(poses.isEmpty)
        for pose in poses {
            XCTAssertGreaterThan(hypot(pose.offset.dx, pose.offset.dy), 10)
            XCTAssertLessThan(pose.alpha, 1)
        }
    }

    func testEverythingIsGoneAfterTheDurationWhichStaysShort() {
        for style in CommitEffectStyle.allCases {
            let effect = effect(style, .rainbow)

            XCTAssertLessThan(effect.duration, 1, "\(style)")
            XCTAssertTrue(effect.fragments.allSatisfy { effect.pose(of: $0, at: effect.duration + 0.001) == nil }, "\(style)")
        }
    }

    func testAccentPaletteKeepsTheSnapshot() {
        XCTAssertTrue(effect(.shatter, .accent).fragments.allSatisfy { $0.tint == nil })
        XCTAssertTrue(effect(.crumble, .accent).fragments.allSatisfy { $0.tint == nil })
    }

    func testGlassShardsTakePaletteColors() {
        let palette = CommitEffectPalette.neon.colors!
        let shards = effect(.shatter, .neon).fragments

        XCTAssertTrue(shards.allSatisfy { shard in palette.contains { $0 == shard.tint } })
        XCTAssertGreaterThan(Set(shards.compactMap { $0.tint?.description }).count, 2, "confetti uses several colors")
    }

    func testCrumbleRunsThroughThePaletteLeftToRight() {
        let pieces = effect(.crumble, .rainbow).fragments.sorted { $0.centroid.x < $1.centroid.x }
        let first = CommitEffectPalette.rainbow.colors!.first!

        XCTAssertLessThan(distance(pieces.first!.tint!, first), distance(pieces.last!.tint!, first))
    }

    func testDustKeepsTextWhiteAndRecolorsTheRest() {
        let blue = NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)
        let textColumn: ClosedRange<CGFloat> = 40...60
        let dust = CommitEffect(
            style: .dust, palette: .rainbow, rowSize: row,
            pixelColor: { textColumn.contains($0.x) ? .white : blue },
            isText: { textColumn.contains($0.x) },
            seed: 1
        )

        for particle in dust.fragments {
            if textColumn.contains(particle.centroid.x) {
                XCTAssertEqual(particle.color, .white)
            } else {
                XCTAssertNotEqual(particle.color, blue)
            }
        }
    }

    func testTransparentCellsMakeNoDust() {
        let dust = CommitEffect(style: .dust, palette: .accent, rowSize: row, pixelColor: { $0.x < 30 ? .clear : .white }, seed: 1)

        XCTAssertTrue(dust.fragments.allSatisfy { $0.centroid.x >= 30 })
    }

    private func effect(_ style: CommitEffectStyle, _ palette: CommitEffectPalette, seed: UInt64 = 7) -> CommitEffect {
        CommitEffect(style: style, palette: palette, rowSize: row, pixelColor: { _ in .systemBlue }, seed: seed)
    }

    private func area(of polygon: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for (i, p) in polygon.enumerated() {
            let q = polygon[(i + 1) % polygon.count]
            sum += p.x * q.y - q.x * p.y
        }
        return abs(sum) / 2
    }

    private func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
    }
}
