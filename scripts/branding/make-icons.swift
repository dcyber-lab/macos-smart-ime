// Generates the LinguaType input method icons.
//
// Usage: swift scripts/branding/make-icons.swift [preview-directory]
//
// Writes apps/ime/Resources/LinguaType.tiff (16 pt template menu icon with 1x and 2x bitmaps:
// rounded square with "中" and "A" cut out) and apps/ime/Resources/LinguaType.icns (gradient app
// icon with white glyphs). With a preview directory, also writes PNG previews of both.
//
// The menu icon is a bitmap TIFF, like the system's own template input method icons (e.g. Ainu.tiff):
// the input menu drew a PDF version as a solid square.

import AppKit
import CoreText

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let resources = repoRoot.appendingPathComponent("apps/ime/Resources")
let previewDirectory = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil

func glyphPath(_ character: String, font: CTFont) -> CGPath {
    var characters = Array(character.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count),
          let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        fatalError("no glyph for \(character) in \(CTFontCopyPostScriptName(font))")
    }
    return path
}

func placed(_ path: CGPath, centeredAt center: CGPoint) -> CGPath {
    let box = path.boundingBoxOfPath
    var transform = CGAffineTransform(translationX: center.x - box.midX, y: center.y - box.midY)
    return path.copy(using: &transform)!
}

func hanFont(_ size: CGFloat) -> CTFont {
    CTFontCreateWithName("PingFangSC-Semibold" as CFString, size, nil)
}

func latinFont(_ size: CGFloat) -> CTFont {
    NSFont.systemFont(ofSize: size, weight: .semibold) as CTFont
}

/// Glyph layout in a unit square: "中" top left, "A" bottom right.
func glyphs(in box: CGRect) -> CGPath {
    let unit = box.width
    let path = CGMutablePath()
    path.addPath(placed(glyphPath("中", font: hanFont(unit * 0.50)),
                        centeredAt: CGPoint(x: box.minX + unit * 0.35, y: box.minY + unit * 0.64)))
    path.addPath(placed(glyphPath("A", font: latinFont(unit * 0.50)),
                        centeredAt: CGPoint(x: box.minX + unit * 0.69, y: box.minY + unit * 0.32)))
    return path
}

// MARK: Menu icon (template PDF)

let menuSize: CGFloat = 16
let menuBox = CGRect(x: 0.5, y: 0.5, width: menuSize - 1, height: menuSize - 1)
let menuBackground = CGPath(roundedRect: menuBox, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
let evenOddPath = CGMutablePath()
evenOddPath.addPath(menuBackground)
evenOddPath.addPath(glyphs(in: menuBox))
// The input menu fills icons with the nonzero winding rule, which filled the glyph "holes" of an
// even-odd path solid. Subtract the glyphs instead so the holes survive any fill rule.
let menuPath = menuBackground.subtracting(glyphs(in: menuBox), using: .evenOdd)

func menuBitmap(scale: Int) -> NSBitmapImageRep {
    let pixels = Int(menuSize) * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.addPath(menuPath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath(using: .winding)
    NSGraphicsContext.restoreGraphicsState()
    // Set the point size only after drawing; a 32 px rep sized at 16 pt already draws at 2x.
    rep.size = NSSize(width: menuSize, height: menuSize)
    return rep
}

let menuImage = NSImage(size: NSSize(width: menuSize, height: menuSize))
menuImage.addRepresentation(menuBitmap(scale: 1))
menuImage.addRepresentation(menuBitmap(scale: 2))
let tiffURL = resources.appendingPathComponent("LinguaType.tiff")
try menuImage.tiffRepresentation(using: .lzw, factor: 0)!.write(to: tiffURL)
print("wrote \(tiffURL.path)")

// MARK: App icon

func appIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824 pt rounded square centered in 1024.
    let square = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: square, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [NSColor(srgbRed: 0.31, green: 0.27, blue: 0.90, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.08, green: 0.72, blue: 0.65, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: square.minX, y: square.maxY),
                               end: CGPoint(x: square.maxX, y: square.minY), options: [])
    let highlight = [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
    let shine = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: highlight, locations: [0, 1])!
    context.drawLinearGradient(shine, start: CGPoint(x: square.midX, y: square.maxY),
                               end: CGPoint(x: square.midX, y: square.midY), options: [])
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    context.addPath(glyphs(in: square))
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("LinguaType.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try appIcon(pixels: points * scale).representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent(name))
}
let icnsURL = resources.appendingPathComponent("LinguaType.icns")
let iconutil = try Process.run(URL(fileURLWithPath: "/usr/bin/iconutil"),
                               arguments: ["-c", "icns", "-o", icnsURL.path, iconset.path])
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("wrote \(icnsURL.path)")

// MARK: Previews

if let previewDirectory {
    try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
    // Menu icon at 1x, 2x, and 8x on light and dark bars, tinted the way macOS draws template images.
    let scales: [CGFloat] = [1, 2, 8]
    let barHeight: CGFloat = 24 * 8
    let width = scales.reduce(CGFloat(24)) { $0 + menuSize * $1 + 24 }
    let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(barHeight * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
    let context = NSGraphicsContext.current!.cgContext
    for (row, (background, foreground)) in [(NSColor(white: 0.93, alpha: 1), NSColor(white: 0.1, alpha: 1)),
                                           (NSColor(white: 0.16, alpha: 1), NSColor(white: 0.95, alpha: 1))].enumerated() {
        let y = CGFloat(row) * barHeight
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: y, width: width, height: barHeight))
        var x: CGFloat = 24
        for scale in scales {
            context.saveGState()
            context.translateBy(x: x, y: y + (barHeight - menuSize * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.addPath(menuPath)
            context.setFillColor(foreground.cgColor)
            context.fillPath(using: .winding)
            context.restoreGState()
            x += menuSize * scale + 24
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try preview.representation(using: .png, properties: [:])!.write(to: previewDirectory.appendingPathComponent("menu-icon.png"))
    try appIcon(pixels: 512).representation(using: .png, properties: [:])!.write(to: previewDirectory.appendingPathComponent("app-icon.png"))
    print("wrote previews to \(previewDirectory.path)")
}
