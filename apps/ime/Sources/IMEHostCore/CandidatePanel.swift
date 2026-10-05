import AppKit
import SharedModels

/// Host-drawn vertical candidate panel shared by all input controllers in the process.
@MainActor
final class CandidatePanel {
    static let shared = CandidatePanel()

    static let cornerRadius: CGFloat = 14

    /// The fade after a commit effect starts.
    static let commitFadeDuration: TimeInterval = 0.1

    private let window: NSPanel
    private let listView = CandidateListView()
    private var lastCaretRect: CGRect?
    /// Set by `playCommitEffect`; the next `hide()` fades instead of disappearing.
    private var fadesOnHide = false
    /// Bumped by every show and fade, so a stale fade never hides a newer panel.
    private var generation = 0

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

        fadesOnHide = false
        generation += 1
        if window.alphaValue < 1 {
            // A zero-length animation replaces a running fade.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                window.animator().alphaValue = 1
            }
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
        guard fadesOnHide, window.isVisible else {
            window.orderOut(nil)
            return
        }
        fadesOnHide = false
        generation += 1
        let fade = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.commitFadeDuration
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == fade else {
                    return
                }
                self.window.orderOut(nil)
                self.window.alphaValue = 1
            }
        }
    }

    /// Breaks the row showing `committedText` apart in the effect overlay and blanks it here, so the
    /// following `hide()` fades the rest of the panel. Does nothing when no visible row matches.
    func playCommitEffect(for committedText: String, style: CommitEffectStyle, palette: CommitEffectPalette) {
        guard window.isVisible,
              let index = CandidatePanelModel.committedRowIndex(in: listView.rows, committedText: committedText)
        else {
            return
        }
        // A number key or click may pick a row that is not highlighted; draw it highlighted for the snapshot.
        listView.rows = CandidatePanelModel.highlighting(listView.rows, at: index)
        let rowRects = listView.rowRects()
        guard rowRects.indices.contains(index), let snapshot = listView.snapshotRow(at: index) else {
            return
        }
        let screenRect = window.convertToScreen(listView.convert(rowRects[index], to: nil))
        Self.playEffect(style: style, palette: palette, snapshot: snapshot, at: screenRect)

        listView.rows = CandidatePanelModel.vacating(listView.rows, at: index)
        fadesOnHide = true
    }

    /// Plays an effect on a sample row below `point` (screen coordinates), for the input menu.
    func previewCommitEffect(style: CommitEffectStyle, palette: CommitEffectPalette, below point: CGPoint) {
        let sample = CandidateListView()
        sample.appearance = NSApp.effectiveAppearance
        sample.rows = CandidatePanelModel.rows(for: CompositionState(
            mode: .english, compositionText: "preview",
            candidates: [Candidate(text: "LinguaType", source: .rime)], selectedCandidateIndex: 0
        ))
        sample.frame = CGRect(origin: .zero, size: sample.fittingSize)
        guard let snapshot = sample.snapshotRow(at: 0) else {
            return
        }
        let rowRect = CGRect(x: point.x - snapshot.size.width / 2, y: point.y - 40 - snapshot.size.height,
                             width: snapshot.size.width, height: snapshot.size.height)
        Self.playEffect(style: style, palette: palette, snapshot: snapshot, at: rowRect)
    }

    /// Only the snapshot is taken while the key is being handled; building the fragments and their
    /// bitmaps (up to about 5 ms for a long row) waits until the input method has answered the key.
    private static func playEffect(style: CommitEffectStyle, palette: CommitEffectPalette, snapshot: RowSnapshot, at screenRect: CGRect) {
        Task { @MainActor in
            let effect = CommitEffect(
                style: style, palette: palette, rowSize: snapshot.size,
                pixelColor: snapshot.color(at:), isText: snapshot.isText(at:), seed: UInt64.random(in: 1...UInt64.max)
            )
            CommitEffectOverlay.shared.play(effect, snapshot: snapshot, rowRect: screenRect)
        }
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
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
        static let outerPadding: CGFloat = 6
        static let rowHorizontalPadding: CGFloat = 9
        static let rowVerticalPadding: CGFloat = 5
        static let columnGap: CGFloat = 8
        static let tagGap: CGFloat = 10
        static let annotationGap: CGFloat = 6
        static let tagHorizontalPadding: CGFloat = 5
        static let tagVerticalPadding: CGFloat = 1
        static let separatorSpacing: CGFloat = 7
        static let highlightRadius: CGFloat = 8
        static let headerVerticalPadding: CGFloat = 4
        static let headerSeparatorSpacing: CGFloat = 5
        static let chevronGap: CGFloat = 12
        static let chevronSpacing: CGFloat = 4
    }

    private let textFont = NSFont.systemFont(ofSize: 17)
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private let tagFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private let headerFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private let annotationFont = NSFont.systemFont(ofSize: 12)
    private let chevronConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)

    var header: CandidatePanelHeader? {
        didSet { needsDisplay = true }
    }
    var rows: [CandidatePanelRow] = [] {
        didSet { needsDisplay = true }
    }
    var onSelect: ((Int) -> Void)?
    /// Off while snapshotting a row's text alone for colored commit-effect fragments.
    private var drawsHighlightFill = true

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
            + Metrics.headerSeparatorSpacing
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
        let textWidth = rows.map(contentWidth(of:)).max() ?? 0
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

        let onHighlight = NSColor.white.withAlphaComponent(0.8)
        let labelWidth = labelColumnWidth
        for (row, rect) in zip(rows, rowRects()) {
            if row.hasSeparatorBefore {
                drawSeparator(above: rect)
            }
            if row.isHighlighted, drawsHighlightFill {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: Metrics.highlightRadius, yRadius: Metrics.highlightRadius).fill()
            }

            let contentX = rect.minX + Metrics.rowHorizontalPadding
            draw(row.label, font: labelFont, color: row.isHighlighted ? onHighlight : .tertiaryLabelColor,
                 at: contentX + labelWidth - row.label.size(withAttributes: [.font: labelFont]).width, in: rect)
            let textX = contentX + labelWidth + Metrics.columnGap
            draw(row.text, font: textFont, color: row.isHighlighted ? .white : .labelColor, at: textX, in: rect)
            if let annotation = row.annotation {
                let annotationX = textX + row.text.size(withAttributes: [.font: textFont]).width + Metrics.annotationGap
                draw(annotation, font: annotationFont, color: row.isHighlighted ? onHighlight : .secondaryLabelColor,
                     at: annotationX, in: rect)
            }
            if let tag = row.tag {
                drawTag(tag, onHighlight: row.isHighlighted, rightEdge: rect.maxX - Metrics.rowHorizontalPadding, in: rect)
            }
        }

        NSColor.separatorColor.setStroke()
        let radius = CandidatePanel.cornerRadius
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        border.lineWidth = 0.5
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = rowRects().firstIndex(where: { $0.contains(point) }) else {
            return
        }
        onSelect?(index)
    }

    /// Candidate text plus its annotation, if any.
    private func contentWidth(of row: CandidatePanelRow) -> CGFloat {
        let text = row.text.size(withAttributes: [.font: textFont]).width
        guard let annotation = row.annotation else {
            return text
        }
        return text + Metrics.annotationGap + annotation.size(withAttributes: [.font: annotationFont]).width
    }

    /// The row as drawn and its text alone, for the commit effect.
    func snapshotRow(at index: Int) -> RowSnapshot? {
        let rects = rowRects()
        guard rects.indices.contains(index) else {
            return nil
        }
        let rect = rects[index]
        func capture() -> NSBitmapImageRep? {
            guard let rep = bitmapImageRepForCachingDisplay(in: rect) else {
                return nil
            }
            effectiveAppearance.performAsCurrentDrawingAppearance {
                cacheDisplay(in: rect, to: rep)
            }
            return rep
        }
        guard let full = capture() else {
            return nil
        }
        drawsHighlightFill = false
        defer { drawsHighlightFill = true }
        guard let textOnly = capture() else {
            return nil
        }
        return RowSnapshot(full: full, textOnly: textOnly, size: rect.size)
    }

    func rowRects() -> [CGRect] {
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
            height: headerHeight - Metrics.headerSeparatorSpacing
        )
        draw(header.text, font: headerFont, color: .secondaryLabelColor, at: rect.minX + Metrics.rowHorizontalPadding, in: rect)
        drawSeparator(atY: rect.maxY + Metrics.headerSeparatorSpacing / 2,
                      from: rect.minX + Metrics.rowHorizontalPadding, to: rect.maxX - Metrics.rowHorizontalPadding)

        guard showsChevrons else {
            return
        }
        // Fixed slots (up, then down); the unavailable direction is dimmed so the pair reads as one control.
        let downX = rect.maxX - Metrics.rowHorizontalPadding - chevronSlotWidth
        let upX = downX - Metrics.chevronSpacing - chevronSlotWidth
        drawChevron("chevron.up", atX: upX, in: rect, enabled: header.canPageUp)
        drawChevron("chevron.down", atX: downX, in: rect, enabled: header.canPageDown)
    }

    private func chevron(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(chevronConfiguration)
    }

    private func drawChevron(_ name: String, atX x: CGFloat, in rect: CGRect, enabled: Bool) {
        guard let symbol = chevron(name) else {
            return
        }
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            (enabled ? NSColor.secondaryLabelColor : NSColor.quaternaryLabelColor).set()
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

    /// `onHighlight` is true when the tag sits on the accent-filled highlighted row.
    private func drawTag(_ tag: String, onHighlight: Bool, rightEdge: CGFloat, in rect: CGRect) {
        let size = tagSize(for: tag)
        let capsule = CGRect(x: rightEdge - size.width, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        (onHighlight ? NSColor.white.withAlphaComponent(0.25) : NSColor.quaternaryLabelColor).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        draw(tag, font: tagFont, color: onHighlight ? .white : .secondaryLabelColor,
             at: capsule.minX + Metrics.tagHorizontalPadding, in: capsule)
    }

    private func drawSeparator(above rect: CGRect) {
        drawSeparator(atY: rect.minY - Metrics.separatorSpacing / 2,
                      from: rect.minX + Metrics.rowHorizontalPadding, to: rect.maxX - Metrics.rowHorizontalPadding)
    }

    private func drawSeparator(atY y: CGFloat, from minX: CGFloat, to maxX: CGFloat) {
        let line = NSBezierPath()
        line.move(to: CGPoint(x: minX, y: y))
        line.line(to: CGPoint(x: maxX, y: y))
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
