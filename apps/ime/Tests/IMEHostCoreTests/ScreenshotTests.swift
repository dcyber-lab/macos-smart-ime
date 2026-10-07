import AppKit
import XCTest
@testable import IMEHostCore

final class ScreenshotGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func testRectFromTwoPointsIsNormalized() {
        XCTAssertEqual(ScreenshotGeometry.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20)), CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    func testHandleHitTesting() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(ScreenshotGeometry.handle(at: CGPoint(x: 103, y: 98), in: r), .bottomLeft)
        XCTAssertEqual(ScreenshotGeometry.handle(at: CGPoint(x: 200, y: 200), in: r), .top)
        XCTAssertEqual(ScreenshotGeometry.handle(at: CGPoint(x: 300, y: 150), in: r), .right)
        XCTAssertNil(ScreenshotGeometry.handle(at: CGPoint(x: 150, y: 150), in: r))
    }

    func testResizeMovesHeldEdgesFlipsAndClamps() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(ScreenshotGeometry.resize(r, handle: .right, to: CGPoint(x: 400, y: 0), bounds: bounds), CGRect(x: 100, y: 100, width: 300, height: 100))
        XCTAssertEqual(ScreenshotGeometry.resize(r, handle: .left, to: CGPoint(x: 350, y: 0), bounds: bounds), CGRect(x: 300, y: 100, width: 50, height: 100))
        XCTAssertEqual(ScreenshotGeometry.resize(r, handle: .topRight, to: CGPoint(x: 2000, y: 900), bounds: bounds), CGRect(x: 100, y: 100, width: 900, height: 500))
    }

    func testMoveStaysOnScreen() {
        let r = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(ScreenshotGeometry.move(r, by: -500, 50, within: bounds), CGRect(x: 0, y: 150, width: 200, height: 100))
        XCTAssertEqual(ScreenshotGeometry.move(r, by: 0, 800, within: bounds), CGRect(x: 100, y: 500, width: 200, height: 100))
    }

    func testPixelAlignmentSnapsOutward() {
        XCTAssertEqual(
            ScreenshotGeometry.pixelAligned(CGRect(x: 10.3, y: 20.7, width: 99.6, height: 50.1), scale: 2),
            CGRect(x: 10, y: 20.5, width: 100, height: 50.5)
        )
    }

    func testPixelRectFlipsToTopLeftOrigin() {
        let pixels = ScreenshotGeometry.pixelRect(of: CGRect(x: 10, y: 500, width: 100, height: 50), scale: 2, viewHeight: 600)
        XCTAssertEqual(pixels, CGRect(x: 20, y: 100, width: 200, height: 100))
        XCTAssertEqual(ScreenshotGeometry.viewRect(ofPixels: pixels, scale: 2, viewHeight: 600), CGRect(x: 10, y: 500, width: 100, height: 50))
    }

    func testWindowPickTakesFrontmostAndTrimsToScreen() {
        let front = CGRect(x: 900, y: 100, width: 300, height: 200)
        let back = CGRect(x: 0, y: 0, width: 1000, height: 600)
        XCTAssertEqual(ScreenshotGeometry.window(at: CGPoint(x: 950, y: 150), in: [front, back], bounds: bounds), CGRect(x: 900, y: 100, width: 100, height: 200))
        XCTAssertEqual(ScreenshotGeometry.window(at: CGPoint(x: 50, y: 50), in: [front, back], bounds: bounds), back)
        XCTAssertEqual(ScreenshotGeometry.window(at: CGPoint(x: 50, y: 50), in: [front], bounds: bounds), bounds)
    }

    func testWindowBoundsBecomeViewCoordinates() {
        // Primary display 1000×600; a second display above it at (0, 600) in AppKit coordinates.
        let window = CGRect(x: 100, y: 50, width: 300, height: 200)
        XCTAssertEqual(
            ScreenshotGeometry.viewRect(ofWindowBounds: window, primaryHeight: 600, screenOrigin: .zero),
            CGRect(x: 100, y: 350, width: 300, height: 200)
        )
        let above = CGRect(x: 100, y: -500, width: 300, height: 200)
        XCTAssertEqual(
            ScreenshotGeometry.viewRect(ofWindowBounds: above, primaryHeight: 600, screenOrigin: CGPoint(x: 0, y: 600)),
            CGRect(x: 100, y: 300, width: 300, height: 200)
        )
    }

    func testToolbarGoesBelowThenAboveThenInside() {
        let size = CGSize(width: 400, height: 40)
        XCTAssertEqual(ScreenshotGeometry.toolbarOrigin(size: size, selection: CGRect(x: 300, y: 200, width: 500, height: 200), bounds: bounds), CGPoint(x: 400, y: 152))
        XCTAssertEqual(ScreenshotGeometry.toolbarOrigin(size: size, selection: CGRect(x: 300, y: 10, width: 500, height: 200), bounds: bounds), CGPoint(x: 400, y: 218))
        XCTAssertEqual(ScreenshotGeometry.toolbarOrigin(size: size, selection: CGRect(x: 0, y: 0, width: 100, height: 600), bounds: bounds), CGPoint(x: 4, y: 8))
    }

    func testMagnifierFlipsAtScreenEdges() {
        let size = CGSize(width: 120, height: 158)
        XCTAssertEqual(ScreenshotGeometry.magnifierOrigin(size: size, cursor: CGPoint(x: 100, y: 400), bounds: bounds), CGPoint(x: 118, y: 224))
        XCTAssertEqual(ScreenshotGeometry.magnifierOrigin(size: size, cursor: CGPoint(x: 950, y: 50), bounds: bounds), CGPoint(x: 812, y: 68))
    }
}

final class ScreenshotRendererTests: XCTestCase {
    /// 200×100 points at 2x: red on the left half, blue on the right.
    private func splitCanvas() -> ScreenshotCanvas {
        let ctx = Self.context(width: 400, height: 200)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
        return ScreenshotCanvas(image: ctx.makeImage()!, size: CGSize(width: 200, height: 100))
    }

    func testRendersSelectionAtFullResolution() throws {
        let image = try XCTUnwrap(ScreenshotRenderer.image(canvas: splitCanvas(), selection: CGRect(x: 50, y: 0, width: 100, height: 100), annotations: []))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 200)
        XCTAssertEqual(Self.rgb(image, x: 10, y: 100), [255, 0, 0])
        XCTAssertEqual(Self.rgb(image, x: 190, y: 100), [0, 0, 255])
    }

    func testCropKeepsTopAndBottom() throws {
        // Top half white, bottom half black, 100×100 points at 1x.
        let ctx = Self.context(width: 100, height: 100)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        let canvas = ScreenshotCanvas(image: ctx.makeImage()!, size: CGSize(width: 100, height: 100))

        let top = try XCTUnwrap(ScreenshotRenderer.image(canvas: canvas, selection: CGRect(x: 0, y: 60, width: 20, height: 20), annotations: []))
        let bottom = try XCTUnwrap(ScreenshotRenderer.plainImage(canvas: canvas, selection: CGRect(x: 0, y: 10, width: 20, height: 20)))
        XCTAssertEqual(Self.rgb(top, x: 10, y: 10), [255, 255, 255])
        XCTAssertEqual(Self.rgb(bottom, x: 10, y: 10), [0, 0, 0])
    }

    func testAnnotationsAreDrawnOnlyInTheRenderedImage() throws {
        let canvas = splitCanvas()
        let selection = CGRect(x: 0, y: 0, width: 100, height: 100)
        let mark = ScreenshotAnnotation(shape: .rectangle(CGRect(x: 20, y: 20, width: 60, height: 60)), style: ScreenshotStyle(color: .green, size: .large))
        let marked = try XCTUnwrap(ScreenshotRenderer.image(canvas: canvas, selection: selection, annotations: [mark]))
        let plain = try XCTUnwrap(ScreenshotRenderer.plainImage(canvas: canvas, selection: selection))

        // The left edge of the rectangle, at x = 20 pt (40 px), halfway up.
        XCTAssertEqual(Double(Self.rgb(marked, x: 40, y: 100)[1]), 199, accuracy: 3)
        XCTAssertEqual(Self.rgb(plain, x: 40, y: 100), [255, 0, 0])
        XCTAssertEqual(Self.rgb(marked, x: 100, y: 100), [255, 0, 0])
    }

    func testMosaicMakesUniformBlocks() throws {
        // A horizontal gradient: every column differs.
        let ctx = Self.context(width: 100, height: 100)
        for x in 0..<100 {
            ctx.setFillColor(CGColor(gray: CGFloat(x) / 99, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: 100))
        }
        let canvas = ScreenshotCanvas(image: ctx.makeImage()!, size: CGSize(width: 100, height: 100))
        let mosaic = ScreenshotAnnotation(shape: .mosaic(CGRect(x: 0, y: 0, width: 100, height: 100)), style: ScreenshotStyle(size: .medium))
        let image = try XCTUnwrap(ScreenshotRenderer.image(canvas: canvas, selection: CGRect(x: 0, y: 0, width: 100, height: 100), annotations: [mosaic]))

        // Blocks are 10 px: the columns of one block match, neighboring blocks do not.
        XCTAssertEqual(Self.rgb(image, x: 21, y: 50), Self.rgb(image, x: 28, y: 50))
        XCTAssertNotEqual(Self.rgb(image, x: 28, y: 50), Self.rgb(image, x: 31, y: 50))
    }

    func testArrowHeadEndsAtTheTip() {
        let head = ScreenshotRenderer.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), lineWidth: 4)
        XCTAssertEqual(head.tip, CGPoint(x: 100, y: 0))
        XCTAssertEqual(head.left.x, 84, accuracy: 0.001)
        XCTAssertEqual(head.left.y, -head.right.y, accuracy: 0.001)
        XCTAssertGreaterThan(head.left.y, 0)
        XCTAssertLessThan(head.shaftEnd.x, 100)
    }

    func testPNGKeepsPointSize() throws {
        let canvas = splitCanvas()
        let image = try XCTUnwrap(ScreenshotRenderer.image(canvas: canvas, selection: CGRect(x: 0, y: 0, width: 200, height: 100), annotations: []))
        let data = try XCTUnwrap(ScreenshotRenderer.pngData(image, scale: 2))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 400)
        XCTAssertEqual(rep.size.width, 200, accuracy: 0.5)
    }

    func testHexColorReadsThePixel() {
        XCTAssertEqual(ScreenshotOverlayView.hexColor(of: splitCanvas().image, x: 399, y: 0), "#0000FF")
        XCTAssertNil(ScreenshotOverlayView.hexColor(of: splitCanvas().image, x: 400, y: 0))
    }

    static func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    /// Red, green, and blue of the pixel at (x, y) from the top left, in sRGB.
    static func rgb(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * ctx.bytesPerRow + x * 4
        return [data[offset], data[offset + 1], data[offset + 2]]
    }
}

final class ScreenshotOCRTests: XCTestCase {
    func testLinesAreOrderedTopToBottomAndLeftToRight() {
        let lines = [
            ScreenshotOCR.Line(text: "second", box: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.1)),
            ScreenshotOCR.Line(text: "right", box: CGRect(x: 0.6, y: 0.72, width: 0.3, height: 0.1)),
            ScreenshotOCR.Line(text: "left", box: CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.1)),
        ]
        XCTAssertEqual(ScreenshotOCR.text(from: lines), "left right\nsecond")
        XCTAssertEqual(ScreenshotOCR.text(from: []), "")
    }

    func testRecognizesChineseAndEnglish() throws {
        let width = 900, height = 260
        let ctx = ScreenshotRendererTests.context(width: width, height: height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black]
        NSAttributedString(string: "Hello Screenshot", attributes: attributes).draw(at: CGPoint(x: 30, y: 150))
        NSAttributedString(string: "截图识别文字", attributes: attributes).draw(at: CGPoint(x: 30, y: 40))
        NSGraphicsContext.restoreGraphicsState()

        let text = try ScreenshotOCR.recognizeLines(ctx.makeImage()!)
        XCTAssertEqual(text, "Hello Screenshot\n截图识别文字")
    }
}

final class ScreenshotSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var system: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ScreenshotSettingsTests")
        defaults.removePersistentDomain(forName: "ScreenshotSettingsTests")
        system = UserDefaults(suiteName: "ScreenshotSettingsTests.system")
        system.removePersistentDomain(forName: "ScreenshotSettingsTests.system")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ScreenshotSettingsTests")
        system.removePersistentDomain(forName: "ScreenshotSettingsTests.system")
        super.tearDown()
    }

    func testDefaultsAreOnWithControlOptionAAndO() {
        let settings = ScreenshotSettings(defaults: defaults, systemDefaults: system)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.hotkey.displayString, "⌃⌥A")
        XCTAssertEqual(settings.ocrHotkey.displayString, "⌃⌥O")
    }

    func testHotkeysAndSwitchComeFromDefaults() {
        defaults.set("cmd+shift+x", forKey: ScreenshotSettings.hotkeyKey)
        defaults.set("x", forKey: ScreenshotSettings.ocrHotkeyKey)
        ScreenshotSettings.setEnabled(false, defaults: defaults)
        let settings = ScreenshotSettings(defaults: defaults, systemDefaults: system)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.hotkey.displayString, "⇧⌘X")
        XCTAssertEqual(settings.ocrHotkey, ScreenshotSettings.defaultOCRHotkey)
    }

    func testSaveFolderPrefersChoiceThenSystemThenDesktop() {
        XCTAssertEqual(ScreenshotSettings(defaults: defaults, systemDefaults: system).saveFolder.lastPathComponent, "Desktop")
        system.set("~/Pictures/Shots", forKey: "location")
        XCTAssertEqual(
            ScreenshotSettings(defaults: defaults, systemDefaults: system).saveFolder.path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Shots").path
        )
        ScreenshotSettings.setSaveFolder(URL(fileURLWithPath: "/tmp/caps"), defaults: defaults)
        XCTAssertEqual(ScreenshotSettings(defaults: defaults, systemDefaults: system).saveFolder.path, "/tmp/caps")
    }

    func testFileNamesAvoidExistingFiles() {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 10, 5, 9, 3, 7)
        let date = Calendar.current.date(from: components)!
        XCTAssertEqual(ScreenshotSettings.fileName(at: date) { _ in false }, "Screenshot 2026-10-05 09.03.07.png")
        let taken: Set = ["Screenshot 2026-10-05 09.03.07.png", "Screenshot 2026-10-05 09.03.07 (2).png"]
        XCTAssertEqual(ScreenshotSettings.fileName(at: date) { taken.contains($0) }, "Screenshot 2026-10-05 09.03.07 (3).png")
        XCTAssertEqual(
            ScreenshotSettings.fileName(at: date, prefix: "Screen Recording", fileExtension: "mp4") { _ in false },
            "Screen Recording 2026-10-05 09.03.07.mp4"
        )
    }

    func testRecordingDefaultsAndFrameRate() {
        var settings = ScreenshotSettings(defaults: defaults, systemDefaults: system)
        XCTAssertEqual(settings.recordHotkey.displayString, "⌃⌥⇧A")
        XCTAssertEqual(settings.frameRate, 30)
        ScreenshotSettings.setFrameRate(60, defaults: defaults)
        settings = ScreenshotSettings(defaults: defaults, systemDefaults: system)
        XCTAssertEqual(settings.frameRate, 60)
        defaults.set(24, forKey: ScreenshotSettings.frameRateKey)
        XCTAssertEqual(ScreenshotSettings(defaults: defaults, systemDefaults: system).frameRate, 30)
    }
}

final class ScreenRecordingGeometryTests: XCTestCase {
    func testSourceIsTopLeftInDisplayPoints() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let source = try XCTUnwrap(ScreenRecordingGeometry.source(of: CGRect(x: 100, y: 50, width: 300, height: 200), screenFrame: screen, scale: 2))
        XCTAssertEqual(source.rect, CGRect(x: 100, y: 350, width: 300, height: 200))
        XCTAssertEqual(source.pixelWidth, 600)
        XCTAssertEqual(source.pixelHeight, 400)
    }

    func testSourceIsRelativeToItsScreen() throws {
        // A second display to the right of and above the first one, in global Cocoa coordinates.
        let screen = CGRect(x: 1000, y: 200, width: 800, height: 500)
        let source = try XCTUnwrap(ScreenRecordingGeometry.source(of: CGRect(x: 1100, y: 300, width: 100, height: 100), screenFrame: screen, scale: 1))
        XCTAssertEqual(source.rect, CGRect(x: 100, y: 300, width: 100, height: 100))
    }

    func testSourceIsTrimmedToEvenPixelsAndToTheScreen() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let odd = try XCTUnwrap(ScreenRecordingGeometry.source(of: CGRect(x: 10, y: 10, width: 101, height: 51), screenFrame: screen, scale: 1))
        XCTAssertEqual(odd.pixelWidth, 100)
        XCTAssertEqual(odd.pixelHeight, 50)
        XCTAssertEqual(odd.rect.size, CGSize(width: 100, height: 50))
        let outside = try XCTUnwrap(ScreenRecordingGeometry.source(of: CGRect(x: 900, y: -20, width: 300, height: 120), screenFrame: screen, scale: 1))
        XCTAssertEqual(outside.rect, CGRect(x: 900, y: 500, width: 100, height: 100))
        XCTAssertNil(ScreenRecordingGeometry.source(of: CGRect(x: 5, y: 5, width: 1, height: 40), screenFrame: screen, scale: 1))
        XCTAssertNil(ScreenRecordingGeometry.source(of: CGRect(x: 2000, y: 5, width: 100, height: 40), screenFrame: screen, scale: 1))
    }

    func testOutputKeepsSizeUnderTheEncoderLimit() {
        XCTAssertTrue(ScreenRecordingGeometry.outputSize(pixelWidth: 1920, pixelHeight: 1080) == (1920, 1080))
        XCTAssertTrue(ScreenRecordingGeometry.outputSize(pixelWidth: 3840, pixelHeight: 2160) == (3840, 2160))
    }

    func testOutputScalesLargeScreensDownToEvenSizes() {
        let fiveK = ScreenRecordingGeometry.outputSize(pixelWidth: 5120, pixelHeight: 2880)
        XCTAssertLessThanOrEqual(fiveK.width * fiveK.height, ScreenRecordingGeometry.maxPixels)
        XCTAssertEqual(Double(fiveK.width) / Double(fiveK.height), 16.0 / 9.0, accuracy: 0.01)
        let wide = ScreenRecordingGeometry.outputSize(pixelWidth: 6880, pixelHeight: 1000)
        XCTAssertLessThanOrEqual(wide.width, ScreenRecordingGeometry.maxSide)
        for size in [fiveK, wide] {
            XCTAssertEqual(size.width % 2, 0)
            XCTAssertEqual(size.height % 2, 0)
        }
    }

    func testElapsedText() {
        XCTAssertEqual(ScreenRecordingGeometry.elapsedText(7.9), "0:07")
        XCTAssertEqual(ScreenRecordingGeometry.elapsedText(754), "12:34")
        XCTAssertEqual(ScreenRecordingGeometry.elapsedText(3723), "1:02:03")
        XCTAssertEqual(ScreenRecordingGeometry.elapsedText(-1), "0:00")
    }

    func testBitRateScalesWithinBounds() {
        XCTAssertEqual(ScreenRecorder.bitRate(width: 1920, height: 1080, frameRate: 30), 4_976_640)
        XCTAssertEqual(ScreenRecorder.bitRate(width: 200, height: 100, frameRate: 15), 2_000_000)
        XCTAssertEqual(ScreenRecorder.bitRate(width: 3840, height: 2160, frameRate: 60), 24_000_000)
    }
}
