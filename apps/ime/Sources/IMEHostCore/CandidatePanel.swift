import AppKit
import SharedModels

/// Host-drawn vertical candidate panel shared by all input controllers in the process.
@MainActor
final class CandidatePanel {
    static let shared = CandidatePanel()

    static let cornerRadius: CGFloat = 10

    private let window: NSPanel
    private let listView = CandidateListView()
    private var lastCaretRect: CGRect?

    private init() {
        window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        background.addSubview(listView)
        window.contentView = background
    }

    func show(state: CompositionState, caretRect reportedCaretRect: CGRect, onSelect: @escaping (Int) -> Void) {
        let rows = CandidatePanelModel.rows(for: state)
        guard !rows.isEmpty else {
            hide()
            return
        }

        listView.onSelect = onSelect
        listView.rows = rows
        let size = listView.fittingSize

        let caretRect = CandidatePanelPlacement.caretRect(
            reported: reportedCaretRect,
            lastKnown: lastCaretRect,
            mouseLocation: NSEvent.mouseLocation
        )
        lastCaretRect = caretRect
        let screen = NSScreen.screens.first { $0.frame.contains(caretRect.origin) } ?? NSScreen.main
        let origin = CandidatePanelPlacement.origin(
            panelSize: size,
            caretRect: caretRect,
            visibleFrame: screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        )

        window.setFrame(CGRect(origin: origin, size: size), display: true)
        listView.frame = CGRect(origin: .zero, size: size)
        listView.needsDisplay = true
        window.invalidateShadow()
        window.orderFrontRegardless()
    }

    func hide() {
        listView.onSelect = nil
        window.orderOut(nil)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Draws candidate rows top to bottom and reports row clicks.
final class CandidateListView: NSView {
    private enum Metrics {
        static let outerPadding: CGFloat = 5
        static let rowHorizontalPadding: CGFloat = 9
        static let rowVerticalPadding: CGFloat = 4
        static let columnGap: CGFloat = 9
        static let tagGap: CGFloat = 16
        static let separatorSpacing: CGFloat = 9
        static let highlightRadius: CGFloat = 6
        static let minimumWidth: CGFloat = 150
    }

    private let textFont = NSFont.systemFont(ofSize: 16)
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let tagFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    var rows: [CandidatePanelRow] = [] {
        didSet { needsDisplay = true }
    }
    var onSelect: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var rowHeight: CGFloat {
        ceil(textFont.ascender - textFont.descender + textFont.leading) + Metrics.rowVerticalPadding * 2
    }

    private var labelColumnWidth: CGFloat {
        let widest = rows.map { $0.label.size(withAttributes: [.font: labelFont]).width }.max() ?? 0
        return ceil(widest)
    }

    override var fittingSize: NSSize {
        let textWidth = rows.map { $0.text.size(withAttributes: [.font: textFont]).width }.max() ?? 0
        let tagWidth = rows.compactMap { $0.tag?.size(withAttributes: [.font: tagFont]).width }.max()
        var width = Metrics.outerPadding * 2 + Metrics.rowHorizontalPadding * 2
            + labelColumnWidth + Metrics.columnGap + ceil(textWidth)
        if let tagWidth {
            width += Metrics.tagGap + ceil(tagWidth)
        }

        let separators = CGFloat(rows.filter(\.hasSeparatorBefore).count)
        let height = Metrics.outerPadding * 2 + CGFloat(rows.count) * rowHeight + separators * Metrics.separatorSpacing
        return NSSize(width: max(ceil(width), Metrics.minimumWidth), height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let labelWidth = labelColumnWidth
        for (row, rect) in zip(rows, rowRects()) {
            if row.hasSeparatorBefore {
                drawSeparator(above: rect)
            }
            if row.isHighlighted {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: Metrics.highlightRadius, yRadius: Metrics.highlightRadius).fill()
            }

            let highlightedText = NSColor.alternateSelectedControlTextColor
            let contentX = rect.minX + Metrics.rowHorizontalPadding
            draw(row.label, font: labelFont, color: row.isHighlighted ? highlightedText.withAlphaComponent(0.8) : .secondaryLabelColor,
                 at: contentX + labelWidth - row.label.size(withAttributes: [.font: labelFont]).width, in: rect)
            draw(row.text, font: textFont, color: row.isHighlighted ? highlightedText : .labelColor,
                 at: contentX + labelWidth + Metrics.columnGap, in: rect)
            if let tag = row.tag {
                let tagWidth = tag.size(withAttributes: [.font: tagFont]).width
                draw(tag, font: tagFont, color: row.isHighlighted ? highlightedText.withAlphaComponent(0.8) : .tertiaryLabelColor,
                     at: rect.maxX - Metrics.rowHorizontalPadding - tagWidth, in: rect)
            }
        }

        NSColor.separatorColor.setStroke()
        let radius = CandidatePanel.cornerRadius
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = rowRects().firstIndex(where: { $0.contains(point) }) else {
            return
        }
        onSelect?(index)
    }

    private func rowRects() -> [CGRect] {
        var y = Metrics.outerPadding
        return rows.map { row in
            if row.hasSeparatorBefore {
                y += Metrics.separatorSpacing
            }
            let rect = CGRect(
                x: Metrics.outerPadding,
                y: y,
                width: bounds.width - Metrics.outerPadding * 2,
                height: rowHeight
            )
            y += rowHeight
            return rect
        }
    }

    private func drawSeparator(above rect: CGRect) {
        let y = rect.minY - Metrics.separatorSpacing / 2
        let line = NSBezierPath()
        line.move(to: CGPoint(x: rect.minX + Metrics.rowHorizontalPadding, y: y))
        line.line(to: CGPoint(x: rect.maxX - Metrics.rowHorizontalPadding, y: y))
        line.lineWidth = 1
        NSColor.separatorColor.setStroke()
        line.stroke()
    }

    private func draw(_ string: String, font: NSFont, color: NSColor, at x: CGFloat, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let height = string.size(withAttributes: attributes).height
        string.draw(at: CGPoint(x: x, y: rect.midY - height / 2), withAttributes: attributes)
    }
}
