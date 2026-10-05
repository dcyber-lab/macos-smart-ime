import CoreGraphics

/// The eight grips on a selection's border.
enum ScreenshotHandle: CaseIterable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left
}

/// Geometry of the capture overlay, in a screen's view coordinates (points, origin at the bottom left).
enum ScreenshotGeometry {
    static let handleHitRadius: CGFloat = 7
    /// A press that moves less than this is a click (pick the window under it), not a drag.
    static let minimumDrag: CGFloat = 4
    static let margin: CGFloat = 4

    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func handlePoints(for r: CGRect) -> [(ScreenshotHandle, CGPoint)] {
        [
            (.bottomLeft, CGPoint(x: r.minX, y: r.minY)), (.bottom, CGPoint(x: r.midX, y: r.minY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.minY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.topRight, CGPoint(x: r.maxX, y: r.maxY)), (.top, CGPoint(x: r.midX, y: r.maxY)),
            (.topLeft, CGPoint(x: r.minX, y: r.maxY)), (.left, CGPoint(x: r.minX, y: r.midY)),
        ]
    }

    static func handle(at p: CGPoint, in r: CGRect) -> ScreenshotHandle? {
        handlePoints(for: r).first { abs($0.1.x - p.x) <= handleHitRadius && abs($0.1.y - p.y) <= handleHitRadius }?.0
    }

    /// `r` with the edges the handle holds moved to `p` (clamped to `bounds`); dragging past the opposite
    /// edge flips the rectangle.
    static func resize(_ r: CGRect, handle: ScreenshotHandle, to p: CGPoint, bounds: CGRect) -> CGRect {
        let x = min(max(p.x, bounds.minX), bounds.maxX)
        let y = min(max(p.y, bounds.minY), bounds.maxY)
        var (minX, maxX, minY, maxY) = (r.minX, r.maxX, r.minY, r.maxY)
        switch handle {
        case .bottomLeft: (minX, minY) = (x, y)
        case .bottom: minY = y
        case .bottomRight: (maxX, minY) = (x, y)
        case .right: maxX = x
        case .topRight: (maxX, maxY) = (x, y)
        case .top: maxY = y
        case .topLeft: (minX, maxY) = (x, y)
        case .left: minX = x
        }
        return rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
    }

    static func move(_ r: CGRect, by dx: CGFloat, _ dy: CGFloat, within bounds: CGRect) -> CGRect {
        var moved = r.offsetBy(dx: dx, dy: dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// `r` snapped outward to whole pixels.
    static func pixelAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        let minX = (r.minX * scale).rounded(.down) / scale
        let minY = (r.minY * scale).rounded(.down) / scale
        let maxX = (r.maxX * scale).rounded(.up) / scale
        let maxY = (r.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `r` in the pixels of a screen image (origin at the top left), snapped outward to whole pixels.
    static func pixelRect(of r: CGRect, scale: CGFloat, viewHeight: CGFloat) -> CGRect {
        let aligned = pixelAligned(r, scale: scale)
        return CGRect(
            x: (aligned.minX * scale).rounded(), y: ((viewHeight - aligned.maxY) * scale).rounded(),
            width: (aligned.width * scale).rounded(), height: (aligned.height * scale).rounded()
        )
    }

    /// A rectangle in image pixels (origin at the top left) back in view points.
    static func viewRect(ofPixels p: CGRect, scale: CGFloat, viewHeight: CGFloat) -> CGRect {
        CGRect(x: p.minX / scale, y: viewHeight - p.maxY / scale, width: p.width / scale, height: p.height / scale)
    }

    /// The frontmost window containing `p`, trimmed to the screen, else the whole screen.
    static func window(at p: CGPoint, in frames: [CGRect], bounds: CGRect) -> CGRect {
        for frame in frames where frame.contains(p) {
            let visible = frame.intersection(bounds)
            if !visible.isNull, visible.width >= 1, visible.height >= 1 {
                return visible
            }
        }
        return bounds
    }

    /// A window's bounds from `CGWindowListCopyWindowInfo` (global, origin at the top left of the
    /// primary display) in a screen's view coordinates.
    static func viewRect(ofWindowBounds b: CGRect, primaryHeight: CGFloat, screenOrigin: CGPoint) -> CGRect {
        CGRect(x: b.minX - screenOrigin.x, y: primaryHeight - b.maxY - screenOrigin.y, width: b.width, height: b.height)
    }

    /// Below the selection's right edge; above it when there is no room below; inside it otherwise.
    static func toolbarOrigin(size: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 8) -> CGPoint {
        let x = min(max(selection.maxX - size.width, bounds.minX + margin), bounds.maxX - size.width - margin)
        if selection.minY - gap - size.height >= bounds.minY + margin {
            return CGPoint(x: x, y: selection.minY - gap - size.height)
        }
        if selection.maxY + gap + size.height <= bounds.maxY - margin {
            return CGPoint(x: x, y: selection.maxY + gap)
        }
        return CGPoint(x: x, y: max(selection.minY + gap, bounds.minY + margin))
    }

    /// Below and to the right of the pointer, flipped to stay on the screen.
    static func magnifierOrigin(size: CGSize, cursor: CGPoint, bounds: CGRect, offset: CGFloat = 18) -> CGPoint {
        var x = cursor.x + offset
        if x + size.width > bounds.maxX - margin {
            x = cursor.x - offset - size.width
        }
        var y = cursor.y - offset - size.height
        if y < bounds.minY + margin {
            y = cursor.y + offset
        }
        return CGPoint(x: x, y: y)
    }

    /// The size label's origin: above the selection's top left, or inside it at the top when the
    /// selection touches the top of the screen.
    static func sizeLabelOrigin(size: CGSize, selection: CGRect, bounds: CGRect, gap: CGFloat = 6) -> CGPoint {
        let x = min(max(selection.minX, bounds.minX + margin), bounds.maxX - size.width - margin)
        if selection.maxY + gap + size.height <= bounds.maxY {
            return CGPoint(x: x, y: selection.maxY + gap)
        }
        return CGPoint(x: x + gap, y: selection.maxY - gap - size.height)
    }
}
