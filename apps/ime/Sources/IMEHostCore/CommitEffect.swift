import AppKit

/// How a committed candidate row breaks apart.
enum CommitEffectStyle: String, CaseIterable, Sendable {
    /// Cracks flash, then triangular shards burst outward and fall.
    case shatter
    /// The row breaks left to right and the pieces drop.
    case crumble
    /// The row dissolves into fine particles drifting up and right.
    case dust

    var title: String {
        switch self {
        case .shatter: "玻璃炸裂"
        case .crumble: "碎裂下坠"
        case .dust: "粒子消散"
        }
    }
}

enum CommitEffectPalette: String, CaseIterable, Sendable {
    case rainbow
    case neon
    case pastel
    /// The row's own colors: accent fill and white text.
    case accent

    var title: String {
        switch self {
        case .rainbow: "彩虹"
        case .neon: "霓虹"
        case .pastel: "马卡龙"
        case .accent: "跟随强调色"
        }
    }

    /// Nil keeps the row's own colors.
    var colors: [NSColor]? {
        let hexes: [UInt32]
        switch self {
        case .rainbow: hexes = [0xFF3B30, 0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x007AFF, 0x5856D6, 0xAF52DE, 0xFF2D55]
        case .neon: hexes = [0xFF2D95, 0xFF9F1C, 0xE6FF00, 0x39FF14, 0x00E5FF, 0x7A5CFF]
        case .pastel: hexes = [0xFFADC6, 0xFFC8A2, 0xFFE89A, 0xB8F2C2, 0xA0E7F0, 0xB5C7FF, 0xD6B8FF]
        case .accent: return nil
        }
        return hexes.map {
            NSColor(srgbRed: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
        }
    }
}

/// SplitMix64, so an effect is reproducible from its seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct CommitEffectFragment: Equatable {
    /// Polygon in row coordinates (origin top-left, y down).
    var polygon: [CGPoint]
    var centroid: CGPoint
    /// Points per second, y down.
    var velocity: CGVector
    /// Radians per second.
    var spin: CGFloat
    var delay: TimeInterval
    var lifetime: TimeInterval
    var endScale: CGFloat
    /// Dust particles are flat squares of this color; nil draws the snapshot clipped to the polygon.
    var color: NSColor?
    /// The palette color a shard turns into once it moves; nil keeps the snapshot.
    var tint: NSColor?
}

struct CommitEffectPose: Equatable {
    var offset: CGVector
    var rotation: CGFloat
    var scale: CGFloat
    var alpha: CGFloat
}

/// A committed row breaking apart: geometry and timing only, no drawing.
struct CommitEffect {
    let style: CommitEffectStyle
    let rowSize: CGSize
    let fragments: [CommitEffectFragment]
    /// Points per second squared, y down; negative lifts.
    let gravity: CGFloat
    /// Glass only: the intact row shows white cracks before the shards separate.
    let crackDuration: TimeInterval

    var duration: TimeInterval {
        crackDuration + (fragments.map { $0.delay + $0.lifetime }.max() ?? 0)
    }

    /// `pixelColor` samples the row as drawn; `isText` marks dust cells kept white under a colored palette.
    init(
        style: CommitEffectStyle,
        palette: CommitEffectPalette,
        rowSize: CGSize,
        pixelColor: (CGPoint) -> NSColor? = { _ in nil },
        isText: (CGPoint) -> Bool = { _ in false },
        seed: UInt64
    ) {
        self.style = style
        self.rowSize = rowSize
        var rng = SeededGenerator(seed: seed)
        let width = max(rowSize.width, 1)
        switch style {
        case .shatter:
            gravity = 1100
            crackDuration = 0.06
            let impact = CGPoint(x: rowSize.width / 2, y: rowSize.height / 2)
            let reach = max(hypot(rowSize.width, rowSize.height) / 2, 1)
            let shards = Self.triangles(rowSize, columnWidth: 16, rows: 3, rng: &rng) { centroid, rng in
                let dx = centroid.x - impact.x, dy = centroid.y - impact.y
                let distance = hypot(dx, dy)
                let angle = atan2(dy, dx) + .random(in: -0.35...0.35, using: &rng)
                // Faster near the impact, with an upward kick.
                let speed = CGFloat.random(in: 160...320, using: &rng) * (1.15 - 0.4 * distance / reach)
                return Motion(
                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed * 0.8 - .random(in: 80...160, using: &rng)),
                    spin: .random(in: -10...10, using: &rng),
                    delay: Double(distance / reach) * 0.04,
                    lifetime: .random(in: 0.38...0.52, using: &rng),
                    endScale: 0.5
                )
            }
            fragments = Self.tinted(shards, palette, byPosition: false, width: width, rng: &rng)
        case .crumble:
            gravity = 1500
            crackDuration = 0
            let pieces = Self.triangles(rowSize, columnWidth: 15, rows: 2, rng: &rng) { centroid, rng in
                Motion(
                    velocity: CGVector(dx: .random(in: -35...45, using: &rng), dy: .random(in: -50...10, using: &rng)),
                    spin: .random(in: -4...4, using: &rng),
                    delay: Double(centroid.x / width) * 0.16 + .random(in: 0...0.03, using: &rng),
                    lifetime: .random(in: 0.45...0.62, using: &rng),
                    endScale: 0.85
                )
            }
            fragments = Self.tinted(pieces, palette, byPosition: true, width: width, rng: &rng)
        case .dust:
            gravity = -60
            crackDuration = 0
            let cell: CGFloat = 3
            let colors = palette.colors
            var particles: [CommitEffectFragment] = []
            var y: CGFloat = 0
            while y < rowSize.height {
                var x: CGFloat = 0
                while x < rowSize.width {
                    let rect = CGRect(x: x, y: y, width: min(cell, rowSize.width - x), height: min(cell, rowSize.height - y))
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    if var color = pixelColor(center), color.alphaComponent > 0.05 {
                        if let colors, !isText(center) {
                            color = Self.gradient(colors, at: center.x / width + .random(in: -0.04...0.04, using: &rng))
                        }
                        particles.append(CommitEffectFragment(
                            polygon: [rect.origin, CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)],
                            centroid: center,
                            velocity: CGVector(dx: .random(in: 30...130, using: &rng), dy: .random(in: -90 ... -15, using: &rng)),
                            spin: 0,
                            delay: Double(x / width) * 0.2 + .random(in: 0...0.05, using: &rng),
                            lifetime: .random(in: 0.35...0.6, using: &rng),
                            endScale: 0.2,
                            color: color,
                            tint: nil
                        ))
                    }
                    x += cell
                }
                y += cell
            }
            fragments = particles
        }
    }

    /// Seconds since the fragment started moving; zero or less while it is still in place.
    func motionTime(of fragment: CommitEffectFragment, at time: TimeInterval) -> TimeInterval {
        time - crackDuration - fragment.delay
    }

    /// Nil once the fragment has faded out.
    func pose(of fragment: CommitEffectFragment, at time: TimeInterval) -> CommitEffectPose? {
        let t = motionTime(of: fragment, at: time)
        guard t < fragment.lifetime else {
            return nil
        }
        guard t > 0 else {
            return CommitEffectPose(offset: .zero, rotation: 0, scale: 1, alpha: 1)
        }
        let progress = CGFloat(t / fragment.lifetime)
        let u = CGFloat(t)
        return CommitEffectPose(
            offset: CGVector(dx: fragment.velocity.dx * u, dy: fragment.velocity.dy * u + 0.5 * gravity * u * u),
            rotation: fragment.spin * u,
            scale: 1 + (fragment.endScale - 1) * (1 - (1 - progress) * (1 - progress)),
            alpha: 1 - progress * progress
        )
    }

    static func gradient(_ colors: [NSColor], at fraction: CGFloat) -> NSColor {
        guard colors.count > 1 else {
            return colors.first ?? .white
        }
        let x = min(max(fraction, 0), 1) * CGFloat(colors.count - 1)
        let i = min(Int(x), colors.count - 2)
        return colors[i].blended(withFraction: x - CGFloat(i), of: colors[i + 1]) ?? colors[i]
    }

    private struct Motion {
        var velocity: CGVector
        var spin: CGFloat
        var delay: TimeInterval
        var lifetime: TimeInterval
        var endScale: CGFloat
    }

    /// Random colors for glass (confetti), a left-to-right gradient otherwise.
    private static func tinted(
        _ fragments: [CommitEffectFragment], _ palette: CommitEffectPalette, byPosition: Bool, width: CGFloat, rng: inout SeededGenerator
    ) -> [CommitEffectFragment] {
        guard let colors = palette.colors else {
            return fragments
        }
        return fragments.map { fragment in
            var fragment = fragment
            fragment.tint = byPosition
                ? gradient(colors, at: fragment.centroid.x / width + .random(in: -0.06...0.06, using: &rng))
                : colors[Int.random(in: 0..<colors.count, using: &rng)]
            return fragment
        }
    }

    /// A jittered grid split into triangles. Edge vertices stay on the edges, so the pieces tile the row.
    private static func triangles(
        _ size: CGSize, columnWidth: CGFloat, rows: Int, rng: inout SeededGenerator,
        motion: (CGPoint, inout SeededGenerator) -> Motion
    ) -> [CommitEffectFragment] {
        let columns = max(3, Int((size.width / columnWidth).rounded()))
        let cellWidth = size.width / CGFloat(columns), cellHeight = size.height / CGFloat(rows)
        var grid: [[CGPoint]] = []
        for r in 0...rows {
            var line: [CGPoint] = []
            for c in 0...columns {
                var point = CGPoint(x: CGFloat(c) * cellWidth, y: CGFloat(r) * cellHeight)
                if c > 0, c < columns {
                    point.x += .random(in: -cellWidth * 0.35...cellWidth * 0.35, using: &rng)
                }
                if r > 0, r < rows {
                    point.y += .random(in: -cellHeight * 0.3...cellHeight * 0.3, using: &rng)
                }
                line.append(point)
            }
            grid.append(line)
        }

        var result: [CommitEffectFragment] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let a = grid[r][c], b = grid[r][c + 1], d = grid[r + 1][c], e = grid[r + 1][c + 1]
                let pair = Bool.random(using: &rng) ? [[a, b, e], [a, e, d]] : [[a, b, d], [b, e, d]]
                for polygon in pair {
                    let centroid = CGPoint(x: polygon.map(\.x).reduce(0, +) / 3, y: polygon.map(\.y).reduce(0, +) / 3)
                    let m = motion(centroid, &rng)
                    result.append(CommitEffectFragment(
                        polygon: polygon, centroid: centroid, velocity: m.velocity, spin: m.spin,
                        delay: m.delay, lifetime: m.lifetime, endScale: m.endScale, color: nil, tint: nil
                    ))
                }
            }
        }
        return result
    }
}
