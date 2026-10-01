import AppKit

/// A candidate row as drawn (accent fill, white text) and its text alone, for colored fragments.
struct RowSnapshot {
    let image: NSImage
    let text: NSImage
    let size: CGSize
    /// Pixels per point.
    let scale: CGFloat
    private let full: NSBitmapImageRep
    private let textOnly: NSBitmapImageRep

    init(full: NSBitmapImageRep, textOnly: NSBitmapImageRep, size: CGSize) {
        self.full = full
        self.textOnly = textOnly
        self.size = size
        scale = CGFloat(full.pixelsWide) / max(size.width, 1)
        image = NSImage(size: size)
        image.addRepresentation(full)
        text = NSImage(size: size)
        text.addRepresentation(textOnly)
    }

    /// `point` is in row coordinates (origin top-left).
    func color(at point: CGPoint) -> NSColor? {
        pixel(full, point)
    }

    func isText(at point: CGPoint) -> Bool {
        (pixel(textOnly, point)?.alphaComponent ?? 0) > 0.4
    }

    private func pixel(_ rep: NSBitmapImageRep, _ point: CGPoint) -> NSColor? {
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else {
            return nil
        }
        return rep.colorAt(x: x, y: y)
    }
}

/// Draws a `CommitEffect` frame by frame over a row snapshot.
///
/// Each shard is rendered once into a small bitmap when the effect starts (clip, palette fill, sheen,
/// text, edge), so a frame only draws those bitmaps with a transform and alpha, and dust only fills
/// rectangles. That keeps a frame well under a millisecond on the main thread, which also handles keys.
final class CommitEffectView: NSView {
    private struct Sprite {
        /// Bounds in row coordinates.
        let rect: CGRect
        let original: NSImage
        /// The palette look; nil keeps the original.
        let tinted: NSImage?
    }

    private var effect: CommitEffect?
    private var snapshot: RowSnapshot?
    /// Indexed like `effect.fragments`; nil for dust.
    private var sprites: [Sprite?] = []
    private var dustColors: [CGColor?] = []
    /// Where the row sits in this view.
    private var rowOrigin: CGPoint = .zero
    private var startTime: CFTimeInterval = 0
    private var stopClock: (() -> Void)?

    /// Replaceable so frames can be drawn at fixed times offscreen.
    var clock: () -> CFTimeInterval = CACurrentMediaTime
    var isPlaying: Bool { effect != nil }
    private(set) var startedAt: CFTimeInterval = 0
    var onFinish: (() -> Void)?

    override var isFlipped: Bool { true }

    func play(_ effect: CommitEffect, snapshot: RowSnapshot, rowOrigin: CGPoint) {
        stop()
        self.effect = effect
        self.snapshot = snapshot
        self.rowOrigin = rowOrigin
        sprites = effect.fragments.map { $0.color == nil ? Self.sprite($0, style: effect.style, snapshot: snapshot) : nil }
        dustColors = effect.fragments.map { $0.color?.cgColor }
        startTime = clock()
        startedAt = startTime
        startClock()
        needsDisplay = true
    }

    func stop() {
        stopClock?()
        stopClock = nil
        effect = nil
        snapshot = nil
        sprites = []
        dustColors = []
        needsDisplay = true
    }

    private func startClock() {
        if #available(macOS 14.0, *) {
            let link = displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            stopClock = { link.invalidate() }
        } else {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            stopClock = { timer.invalidate() }
        }
    }

    @objc private func tick() {
        guard let effect else {
            return
        }
        if clock() - startTime > effect.duration {
            stop()
            onFinish?()
        } else {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let effect, let snapshot, let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let time = clock() - startTime
        let rowRect = CGRect(origin: rowOrigin, size: effect.rowSize)

        if time < effect.crackDuration {
            drawImage(snapshot.image, in: rowRect, alpha: 1)
            let cracks = NSBezierPath()
            effect.fragments.forEach { cracks.append(path($0.polygon)) }
            NSColor.white.withAlphaComponent(0.85 - 0.4 * time / effect.crackDuration).setStroke()
            cracks.lineWidth = 0.8
            cracks.stroke()
            return
        }

        // Pieces still in place are drawn from the snapshot in one pass, so the intact part of a
        // dissolving row keeps its full resolution.
        let resting = NSBezierPath()
        for (index, fragment) in effect.fragments.enumerated() {
            guard let pose = effect.pose(of: fragment, at: time) else {
                continue
            }
            let moving = effect.motionTime(of: fragment, at: time)
            if moving <= 0 {
                resting.append(path(fragment.polygon))
            } else if let color = dustColors[index] {
                // Dust squares do not rotate: one rectangle fill each.
                let side = fragment.polygon[2].x - fragment.polygon[0].x
                let height = fragment.polygon[2].y - fragment.polygon[0].y
                let center = CGPoint(x: rowOrigin.x + fragment.centroid.x + pose.offset.dx, y: rowOrigin.y + fragment.centroid.y + pose.offset.dy)
                context.setAlpha(pose.alpha)
                context.setFillColor(color)
                context.fill(CGRect(x: center.x - side * pose.scale / 2, y: center.y - height * pose.scale / 2,
                                    width: side * pose.scale, height: height * pose.scale))
            } else if let sprite = sprites[index] {
                drawSprite(sprite, fragment: fragment, pose: pose, moving: moving)
            }
        }
        context.setAlpha(1)
        if !resting.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            resting.addClip()
            drawImage(snapshot.image, in: rowRect, alpha: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawSprite(_ sprite: Sprite, fragment: CommitEffectFragment, pose: CommitEffectPose, moving: TimeInterval) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let center = CGPoint(x: rowOrigin.x + fragment.centroid.x, y: rowOrigin.y + fragment.centroid.y)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x + pose.offset.dx, yBy: center.y + pose.offset.dy)
        transform.rotate(byRadians: pose.rotation)
        transform.scale(by: pose.scale)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        let rect = sprite.rect.offsetBy(dx: rowOrigin.x, dy: rowOrigin.y)
        guard let tinted = sprite.tinted else {
            drawImage(sprite.original, in: rect, alpha: pose.alpha)
            return
        }
        // Shards take on their palette color over the first 80 ms of flight.
        let k = CGFloat(min(1, moving / 0.08))
        if k < 1 {
            drawImage(sprite.original, in: rect, alpha: pose.alpha * (1 - k))
        }
        drawImage(tinted, in: rect, alpha: pose.alpha * k)
    }

    /// The shard as it looks in the row and, with a palette, as it looks in flight.
    private static func sprite(_ fragment: CommitEffectFragment, style: CommitEffectStyle, snapshot: RowSnapshot) -> Sprite {
        let xs = fragment.polygon.map(\.x), ys = fragment.polygon.map(\.y)
        // One point of margin for the edge stroke.
        let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .insetBy(dx: -1, dy: -1).integral
        let shape = NSBezierPath()
        shape.move(to: fragment.polygon[0])
        fragment.polygon.dropFirst().forEach { shape.line(to: $0) }
        shape.close()
        let rowRect = CGRect(origin: .zero, size: snapshot.size)

        func render(_ body: () -> Void) -> NSImage {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: max(1, Int(rect.width * snapshot.scale)), pixelsHigh: max(1, Int(rect.height * snapshot.scale)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            rep.size = rect.size
            if let bitmap = NSGraphicsContext(bitmapImageRep: rep) {
                // Flipped like the row, with the shard's corner at the origin. The bitmap context already
                // maps points to pixels.
                let context = NSGraphicsContext(cgContext: bitmap.cgContext, flipped: true)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                context.cgContext.translateBy(x: 0, y: rect.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                shape.addClip()
                body()
                if style == .shatter {
                    // A faint bright edge reads as glass.
                    NSColor.white.withAlphaComponent(0.4).setStroke()
                    shape.lineWidth = 1
                    shape.stroke()
                }
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
            }
            let image = NSImage(size: rect.size)
            image.addRepresentation(rep)
            return image
        }

        let original = render {
            snapshot.image.draw(in: rowRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let tinted = fragment.tint.map { tint in
            render {
                tint.setFill()
                shape.fill()
                NSGradient(starting: NSColor.white.withAlphaComponent(0.35), ending: .clear)?.draw(in: shape.bounds, angle: 90)
                snapshot.text.draw(in: rowRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        return Sprite(rect: rect, original: original, tinted: tinted)
    }

    private func path(_ polygon: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = polygon.first else {
            return path
        }
        path.move(to: CGPoint(x: rowOrigin.x + first.x, y: rowOrigin.y + first.y))
        for point in polygon.dropFirst() {
            path.line(to: CGPoint(x: rowOrigin.x + point.x, y: rowOrigin.y + point.y))
        }
        path.close()
        return path
    }

    private func drawImage(_ image: NSImage, in rect: CGRect, alpha: CGFloat) {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
    }
}

/// Click-through windows the fragments fly in, one level above the candidate panel.
@MainActor
final class CommitEffectOverlay {
    static let shared = CommitEffectOverlay()

    /// Room around the row for the fragments' flight; more below for gravity.
    static let flight = NSEdgeInsets(top: 140, left: 200, bottom: 260, right: 200)
    private static let poolSize = 3

    private var pool: [(window: NSPanel, view: CommitEffectView)] = []

    private init() {}

    /// `rowRect` is in screen coordinates.
    func play(_ effect: CommitEffect, snapshot: RowSnapshot, rowRect: CGRect) {
        let (window, view) = nextWindow()
        let flight = Self.flight
        window.setFrame(CGRect(
            x: rowRect.minX - flight.left,
            y: rowRect.minY - flight.bottom,
            width: rowRect.width + flight.left + flight.right,
            height: rowRect.height + flight.top + flight.bottom
        ), display: false)
        view.frame = CGRect(origin: .zero, size: window.frame.size)
        view.onFinish = { [weak window] in window?.orderOut(nil) }
        window.orderFrontRegardless()
        view.play(effect, snapshot: snapshot, rowOrigin: CGPoint(x: flight.left, y: flight.top))
    }

    /// An idle window, a new one while the pool is short, or else the oldest effect, cut short.
    private func nextWindow() -> (NSPanel, CommitEffectView) {
        if let idle = pool.first(where: { !$0.view.isPlaying }) {
            return idle
        }
        if pool.count < Self.poolSize {
            let entry = Self.makeWindow()
            pool.append(entry)
            return entry
        }
        let oldest = pool.min { $0.view.startedAt < $1.view.startedAt }!
        oldest.view.stop()
        return oldest
    }

    private static func makeWindow() -> (NSPanel, CommitEffectView) {
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        let view = CommitEffectView()
        window.contentView = view
        return (window, view)
    }
}
