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
        listView.header = CandidatePanelModel.header(for: state)
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

/// Draws the optional preedit header and candidate rows top to bottom, and reports row clicks.
final class CandidateListView: NSView {
    private enum Metrics {
        static let outerPadding: CGFloat = 4
        static let rowHorizontalPadding: CGFloat = 8
        static let rowVerticalPadding: CGFloat = 3
        static let columnGap: CGFloat = 7
        static let tagGap: CGFloat = 12
        static let tagHorizontalPadding: CGFloat = 5
        static let tagVerticalPadding: CGFloat = 1
        static let separatorSpacing: CGFloat = 7
        static let highlightRadius: CGFloat = 6
        static let headerVerticalPadding: CGFloat = 3
        static let chevronGap: CGFloat = 12
        static let chevronSpacing: CGFloat = 4
    }

    private let textFont = NSFont.systemFont(ofSize: 16)
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let tagFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private let headerFont = NSFont.systemFont(ofSize: 12)
    private let chevronConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)

    var header: CandidatePanelHeader? {
        didSet { needsDisplay = true }
    }
    var rows: [CandidatePanelRow] = [] {
        didSet { needsDisplay = true }
    }
    var onSelect: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var rowHeight: CGFloat {
        ceil(textFont.ascender - textFont.descender + textFont.leading) + Metrics.rowVerticalPadding * 2
    }

    private var headerHeight: CGFloat {
        guard header != nil else {
            return 0
        }
        return ceil(headerFont.ascender - headerFont.descender + headerFont.leading) + Metrics.headerVerticalPadding * 2
    }

    private var labelColumnWidth: CGFloat {
        let widest = rows.map { $0.label.size(withAttributes: [.font: labelFont]).width }.max() ?? 0
        return ceil(widest)
    }

    private var chevronSlotWidth: CGFloat {
        ceil(chevron("chevron.down")?.size.width ?? 9)
    }

    private var showsChevrons: Bool {
        guard let header else {
            return false
        }
        return header.canPageUp || header.canPageDown
    }

    override var fittingSize: NSSize {
        let textWidth = rows.map { $0.text.size(withAttributes: [.font: textFont]).width }.max() ?? 0
        let tagWidth = rows.compactMap { $0.tag.map(tagSize(for:))?.width }.max()
        var rowsWidth = Metrics.rowHorizontalPadding * 2 + labelColumnWidth + Metrics.columnGap + ceil(textWidth)
        if let tagWidth {
            rowsWidth += Metrics.tagGap + ceil(tagWidth)
        }

        var headerWidth: CGFloat = 0
        if let header {
            headerWidth = Metrics.rowHorizontalPadding * 2 + ceil(header.text.size(withAttributes: [.font: headerFont]).width)
            if showsChevrons {
                headerWidth += Metrics.chevronGap + chevronSlotWidth * 2 + Metrics.chevronSpacing
            }
        }

        let separators = CGFloat(rows.filter(\.hasSeparatorBefore).count)
        let height = Metrics.outerPadding * 2 + headerHeight + CGFloat(rows.count) * rowHeight
            + separators * Metrics.separatorSpacing
        return NSSize(width: ceil(Metrics.outerPadding * 2 + max(rowsWidth, headerWidth)), height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        if let header {
            drawHeader(header)
        }

        let accent = NSColor.controlAccentColor
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // Plain accent text is too dark on the dark-mode tint; lighten it there.
        let highlightText = isDark ? (accent.blended(withFraction: 0.5, of: .white) ?? .labelColor) : accent
        let labelWidth = labelColumnWidth
        for (row, rect) in zip(rows, rowRects()) {
            if row.hasSeparatorBefore {
                drawSeparator(above: rect)
            }
            if row.isHighlighted {
                accent.withAlphaComponent(isDark ? 0.32 : 0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: Metrics.highlightRadius, yRadius: Metrics.highlightRadius).fill()
            }

            let contentX = rect.minX + Metrics.rowHorizontalPadding
            draw(row.label, font: labelFont, color: row.isHighlighted ? highlightText.withAlphaComponent(0.85) : .secondaryLabelColor,
                 at: contentX + labelWidth - row.label.size(withAttributes: [.font: labelFont]).width, in: rect)
            draw(row.text, font: textFont, color: row.isHighlighted ? highlightText : .labelColor,
                 at: contentX + labelWidth + Metrics.columnGap, in: rect)
            if let tag = row.tag {
                drawTag(tag, highlightText: row.isHighlighted ? highlightText : nil, rightEdge: rect.maxX - Metrics.rowHorizontalPadding, in: rect)
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
        var y = Metrics.outerPadding + headerHeight
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

    private func drawHeader(_ header: CandidatePanelHeader) {
        let rect = CGRect(
            x: Metrics.outerPadding,
            y: Metrics.outerPadding,
            width: bounds.width - Metrics.outerPadding * 2,
            height: headerHeight
        )
        draw(header.text, font: headerFont, color: .secondaryLabelColor, at: rect.minX + Metrics.rowHorizontalPadding, in: rect)

        guard showsChevrons else {
            return
        }
        // Fixed slots (up, then down) so the arrows do not shift while paging.
        let downX = rect.maxX - Metrics.rowHorizontalPadding - chevronSlotWidth
        let upX = downX - Metrics.chevronSpacing - chevronSlotWidth
        if header.canPageUp {
            drawChevron("chevron.up", atX: upX, in: rect)
        }
        if header.canPageDown {
            drawChevron("chevron.down", atX: downX, in: rect)
        }
    }

    private func chevron(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(chevronConfiguration)
    }

    private func drawChevron(_ name: String, atX x: CGFloat, in rect: CGRect) {
        guard let symbol = chevron(name) else {
            return
        }
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            NSColor.secondaryLabelColor.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: CGRect(x: x, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    private func tagSize(for tag: String) -> CGSize {
        let text = tag.size(withAttributes: [.font: tagFont])
        return CGSize(
            width: ceil(text.width) + Metrics.tagHorizontalPadding * 2,
            height: ceil(text.height) + Metrics.tagVerticalPadding * 2
        )
    }

    /// `highlightText` is set when the tag sits on the highlighted row.
    private func drawTag(_ tag: String, highlightText: NSColor?, rightEdge: CGFloat, in rect: CGRect) {
        let size = tagSize(for: tag)
        let capsule = CGRect(x: rightEdge - size.width, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        (highlightText.map { $0.withAlphaComponent(0.2) } ?? NSColor.quaternaryLabelColor).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        draw(tag, font: tagFont, color: highlightText ?? .secondaryLabelColor,
             at: capsule.minX + Metrics.tagHorizontalPadding, in: capsule)
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
