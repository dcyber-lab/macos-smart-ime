import AppKit

enum ScreenshotTool: CaseIterable {
    case rectangle, ellipse, arrow, pen, text, mosaic

    var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .arrow: "Arrow"
        case .pen: "Pen"
        case .text: "Text"
        case .mosaic: "Mosaic"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "scribble"
        case .text: "textformat"
        case .mosaic: "checkerboard.rectangle"
        }
    }

    /// Mosaic hides what is under it, so it has no color.
    var usesColor: Bool {
        self != .mosaic
    }
}

enum ScreenshotColor: CaseIterable {
    case red, yellow, green, blue, white, black

    var cgColor: CGColor {
        switch self {
        case .red: CGColor(srgbRed: 0.96, green: 0.23, blue: 0.21, alpha: 1)
        case .yellow: CGColor(srgbRed: 1, green: 0.78, blue: 0.1, alpha: 1)
        case .green: CGColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1)
        case .blue: CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)
        case .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        }
    }
}

enum ScreenshotStrokeSize: CaseIterable {
    case small, medium, large

    var lineWidth: CGFloat {
        switch self {
        case .small: 2
        case .medium: 4
        case .large: 7
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: 16
        case .medium: 22
        case .large: 32
        }
    }

    /// Mosaic block edge in points.
    var mosaicBlock: CGFloat {
        switch self {
        case .small: 6
        case .medium: 10
        case .large: 16
        }
    }
}

struct ScreenshotStyle: Equatable {
    var color = ScreenshotColor.red
    var size = ScreenshotStrokeSize.medium
}

/// One mark on a capture, in the screen's view coordinates so it stays put when the selection moves.
struct ScreenshotAnnotation: Equatable {
    enum Shape: Equatable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case arrow(from: CGPoint, to: CGPoint)
        case pen([CGPoint])
        /// `topLeft` is the top left corner of the first line.
        case text(String, topLeft: CGPoint)
        case mosaic(CGRect)
    }

    var shape: Shape
    var style: ScreenshotStyle

    static func font(for size: ScreenshotStrokeSize) -> NSFont {
        .systemFont(ofSize: size.fontSize, weight: .semibold)
    }
}

/// A frozen screen: the image of one display and its size in points.
struct ScreenshotCanvas {
    let image: CGImage
    let size: CGSize

    var scale: CGFloat {
        size.width > 0 ? CGFloat(image.width) / size.width : 1
    }
}

/// Draws annotations for the overlay and renders the final image; both share the same drawing code,
/// in view points.
enum ScreenshotRenderer {
    static func draw(_ annotations: [ScreenshotAnnotation], in ctx: CGContext, canvas: ScreenshotCanvas) {
        for annotation in annotations {
            draw(annotation, in: ctx, canvas: canvas)
        }
    }

    static func draw(_ annotation: ScreenshotAnnotation, in ctx: CGContext, canvas: ScreenshotCanvas) {
        let style = annotation.style
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setFillColor(style.color.cgColor)
        ctx.setLineWidth(style.size.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch annotation.shape {
        case .rectangle(let r):
            ctx.stroke(r)
        case .ellipse(let r):
            ctx.strokeEllipse(in: r)
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, lineWidth: style.size.lineWidth, in: ctx)
        case .pen(let points):
            guard let first = points.first else {
                return
            }
            if points.count == 1 {
                let d = style.size.lineWidth
                ctx.fillEllipse(in: CGRect(x: first.x - d / 2, y: first.y - d / 2, width: d, height: d))
                return
            }
            ctx.addLines(between: points)
            ctx.strokePath()
        case .text(let text, let topLeft):
            let string = attributedText(text, style: style)
            let height = string.size().height
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            string.draw(at: CGPoint(x: topLeft.x, y: topLeft.y - height))
            NSGraphicsContext.restoreGraphicsState()
        case .mosaic(let r):
            guard let (tiles, rect) = pixelated(canvas: canvas, rect: r, block: style.size.mosaicBlock) else {
                return
            }
            ctx.interpolationQuality = .none
            ctx.draw(tiles, in: rect)
        }
    }

    static func attributedText(_ text: String, style: ScreenshotStyle) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: ScreenshotAnnotation.font(for: style.size),
            .foregroundColor: NSColor(cgColor: style.color.cgColor) ?? .red,
        ])
    }

    /// The tip and the two back corners of the arrow head, and where the shaft ends.
    static func arrowHead(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (tip: CGPoint, left: CGPoint, right: CGPoint, shaftEnd: CGPoint) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.001)
        let (ux, uy) = (dx / length, dy / length)
        let headLength = min(max(12, lineWidth * 4), length)
        let halfWidth = headLength * 0.45
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        return (
            to,
            CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth),
            CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth),
            CGPoint(x: to.x - ux * headLength * 0.8, y: to.y - uy * headLength * 0.8)
        )
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, in ctx: CGContext) {
        let head = arrowHead(from: from, to: to, lineWidth: lineWidth)
        ctx.move(to: from)
        ctx.addLine(to: head.shaftEnd)
        ctx.strokePath()
        ctx.move(to: head.tip)
        ctx.addLine(to: head.left)
        ctx.addLine(to: head.right)
        ctx.closePath()
        ctx.fillPath()
    }

    /// The part of the canvas under `rect` shrunk to one pixel per block, and the rectangle (snapped to
    /// the canvas's pixels) to stretch it over without smoothing.
    static func pixelated(canvas: ScreenshotCanvas, rect: CGRect, block: CGFloat) -> (CGImage, CGRect)? {
        let scale = canvas.scale
        let bounds = CGRect(x: 0, y: 0, width: canvas.image.width, height: canvas.image.height)
        let pixels = ScreenshotGeometry.pixelRect(of: rect, scale: scale, viewHeight: canvas.size.height).intersection(bounds)
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1, let crop = canvas.image.cropping(to: pixels) else {
            return nil
        }
        let blockPixels = max(1, block * scale)
        let width = max(1, Int((pixels.width / blockPixels).rounded(.up)))
        let height = max(1, Int((pixels.height / blockPixels).rounded(.up)))
        guard let small = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        small.interpolationQuality = .high
        small.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let tiles = small.makeImage() else {
            return nil
        }
        return (tiles, ScreenshotGeometry.viewRect(ofPixels: pixels, scale: scale, viewHeight: canvas.size.height))
    }

    /// The selection with its annotations at the canvas's full resolution.
    static func image(canvas: ScreenshotCanvas, selection: CGRect, annotations: [ScreenshotAnnotation]) -> CGImage? {
        let scale = canvas.scale
        let aligned = ScreenshotGeometry.pixelAligned(selection, scale: scale)
        let pixels = ScreenshotGeometry.pixelRect(of: aligned, scale: scale, viewHeight: canvas.size.height)
        let width = Int(pixels.width), height = Int(pixels.height)
        let space = canvas.image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0, let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -aligned.minX, y: -aligned.minY)
        ctx.interpolationQuality = .none
        ctx.draw(canvas.image, in: CGRect(origin: .zero, size: canvas.size))
        ctx.interpolationQuality = .high
        draw(annotations, in: ctx, canvas: canvas)
        return ctx.makeImage()
    }

    /// The selection without annotations, for text recognition.
    static func plainImage(canvas: ScreenshotCanvas, selection: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: canvas.image.width, height: canvas.image.height)
        let pixels = ScreenshotGeometry.pixelRect(of: selection, scale: canvas.scale, viewHeight: canvas.size.height).intersection(bounds)
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1 else {
            return nil
        }
        return canvas.image.cropping(to: pixels)
    }

    static func pngData(_ image: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        // Points, so the image keeps its on-screen size (144 dpi on a Retina display).
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep.representation(using: .png, properties: [:])
    }
}
