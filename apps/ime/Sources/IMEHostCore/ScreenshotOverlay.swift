import AppKit

/// The capture overlay: every display frozen under a dimmed layer. Hovering highlights the window under
/// the pointer and a click takes it; a drag takes a rectangle. The selection can then be moved, resized,
/// and marked up from the toolbar. In text recognition mode the overlay closes as soon as an area is chosen;
/// in recording mode the toolbar only starts the recording or cancels.
@MainActor
final class ScreenshotOverlay {
    enum Mode {
        case capture
        case recognizeText
        case record

        /// Whether a chosen area stays on screen to be adjusted before the overlay closes.
        var keepsSelection: Bool { self != .recognizeText }
    }

    enum Action {
        case copy, save, pin, recognizeText, record, cancel
    }

    /// What the selection produced: the image with annotations, the plain image for text recognition,
    /// and where it was on screen (global coordinates) for pinning.
    struct Output {
        let image: CGImage
        let plainImage: CGImage
        let scale: CGFloat
        let screenRect: CGRect
    }

    let mode: Mode
    private let snapshots: [ScreenSnapshot]
    private let finishHandler: @MainActor (Action, Output?) -> Void
    private var windows: [ScreenshotOverlayWindow] = []
    private var views: [ScreenshotOverlayView] = []
    private let toolbar: ScreenshotToolbar

    /// The view that holds the selection; only one screen has a selection at a time.
    private(set) weak var selectionView: ScreenshotOverlayView?
    private(set) var selection = CGRect.null
    private(set) var tool: ScreenshotTool?
    private(set) var style = ScreenshotStyle()
    private(set) var annotations: [ScreenshotAnnotation] = []

    init(snapshots: [ScreenSnapshot], mode: Mode, finish: @escaping @MainActor (Action, Output?) -> Void) {
        self.snapshots = snapshots
        self.mode = mode
        self.finishHandler = finish
        toolbar = ScreenshotToolbar(recording: mode == .record)
        toolbar.onTool = { [weak self] in self?.choose(tool: $0) }
        toolbar.onStyle = { [weak self] in self?.choose(style: $0) }
        toolbar.onUndo = { [weak self] in self?.undo() }
        toolbar.onAction = { [weak self] in self?.finish($0) }
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        var keyWindow: ScreenshotOverlayWindow?
        for snapshot in snapshots {
            let window = ScreenshotOverlayWindow(frame: snapshot.screenFrame)
            let view = ScreenshotOverlayView(snapshot: snapshot, overlay: self)
            window.contentView = view.container
            windows.append(window)
            views.append(view)
            if snapshot.screenFrame.contains(mouse) || keyWindow == nil {
                keyWindow = window
            }
        }
        // An accessory app must be active for its window to take the keyboard and set the cursor.
        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            window.orderFrontRegardless()
        }
        keyWindow?.makeKeyAndOrderFront(nil)
        if let keyWindow, let view = views.first(where: { $0.window === keyWindow }) {
            keyWindow.makeFirstResponder(view)
            view.pointerMoved(to: view.convert(keyWindow.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    func close() {
        for view in views {
            view.endTextEditing(commit: false)
        }
        toolbar.removeFromSuperview()
        for window in windows {
            window.orderOut(nil)
        }
        let (closedWindows, closedViews) = (windows, views)
        windows = []
        views = []
        // Torn down on the next turn, since a view may still be handling the event that closed the
        // overlay. Removing each view breaks its cycle with the container that holds the frozen screen.
        DispatchQueue.main.async {
            for view in closedViews {
                view.removeFromSuperview()
            }
            for window in closedWindows {
                window.contentView = nil
            }
        }
    }

    // MARK: Selection

    var hasSelection: Bool {
        selectionView != nil && !selection.isNull
    }

    func select(_ rect: CGRect, in view: ScreenshotOverlayView) {
        if let previous = selectionView, previous !== view {
            previous.needsDisplay = true
        }
        selectionView = view
        selection = rect
        view.needsDisplay = true
        if mode == .recognizeText {
            finish(.recognizeText)
            return
        }
        placeToolbar()
    }

    func updateSelection(_ rect: CGRect) {
        selection = rect
        selectionView?.needsDisplay = true
    }

    /// Back to choosing an area; the marks go with the selection.
    func clearSelection() {
        selectionView?.endTextEditing(commit: false)
        selectionView?.needsDisplay = true
        selectionView = nil
        selection = .null
        annotations = []
        tool = nil
        toolbar.update(tool: nil, style: style, canUndo: false)
        toolbar.removeFromSuperview()
    }

    func setToolbarHidden(_ hidden: Bool) {
        toolbar.isHidden = hidden
        if !hidden {
            placeToolbar()
        }
    }

    private func placeToolbar() {
        guard let view = selectionView, mode.keepsSelection else {
            return
        }
        toolbar.update(tool: tool, style: style, canUndo: !annotations.isEmpty)
        if toolbar.superview !== view {
            view.addSubview(toolbar)
        }
        let size = toolbar.fittingSize
        toolbar.frame = CGRect(
            origin: ScreenshotGeometry.toolbarOrigin(size: size, selection: selection, bounds: view.bounds),
            size: size
        )
    }

    // MARK: Marks

    func choose(tool: ScreenshotTool?) {
        selectionView?.endTextEditing(commit: true)
        self.tool = tool == self.tool ? nil : tool
        placeToolbar()
        selectionView?.refreshCursor()
    }

    func choose(style: ScreenshotStyle) {
        self.style = style
        selectionView?.restyleTextEditing(style)
        placeToolbar()
    }

    func add(_ annotation: ScreenshotAnnotation) {
        annotations.append(annotation)
        selectionView?.needsDisplay = true
        placeToolbar()
    }

    func undo() {
        guard !annotations.isEmpty else {
            return
        }
        annotations.removeLast()
        selectionView?.needsDisplay = true
        placeToolbar()
    }

    // MARK: Finishing

    /// What `Return` and a double-click do.
    var defaultAction: Action {
        switch mode {
        case .capture: .copy
        case .recognizeText: .recognizeText
        case .record: .record
        }
    }

    func finish(_ action: Action) {
        selectionView?.endTextEditing(commit: true)
        guard action != .cancel else {
            finishHandler(.cancel, nil)
            return
        }
        // A recording only needs where the area is; the frozen image is not drawn again for it.
        guard let view = selectionView, hasSelection,
              let plain = ScreenshotRenderer.plainImage(canvas: view.snapshot.canvas, selection: selection),
              let image = action == .record
                ? plain
                : ScreenshotRenderer.image(canvas: view.snapshot.canvas, selection: selection, annotations: annotations) else {
            return
        }
        let aligned = ScreenshotGeometry.pixelAligned(selection, scale: view.snapshot.canvas.scale)
        let output = Output(
            image: image,
            plainImage: plain,
            scale: view.snapshot.canvas.scale,
            screenRect: aligned.offsetBy(dx: view.snapshot.screenFrame.minX, dy: view.snapshot.screenFrame.minY)
        )
        finishHandler(action, output)
    }
}

/// A borderless window over one display, above the menu bar and the Dock.
final class ScreenshotOverlayWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One display's frozen image (in a layer, drawn once) with the interactive layer on top: dimming, the
/// selection and its grips, marks, the size label, the magnifier, and the toolbar.
final class ScreenshotOverlayView: NSView, NSTextViewDelegate {
    private enum Drag {
        case none
        case newSelection(start: CGPoint)
        case move(start: CGPoint, original: CGRect)
        case resize(ScreenshotHandle, original: CGRect)
        case annotate(start: CGPoint)
    }

    private static let dimColor = CGColor(gray: 0, alpha: 0.38)
    private static let magnifierPixels = 15
    private static let magnifierZoom: CGFloat = 8

    let snapshot: ScreenSnapshot
    let container: NSView
    private weak var overlay: ScreenshotOverlay?
    private var pointer: CGPoint?
    private var drag = Drag.none
    /// The rectangle being dragged out before it becomes the selection.
    private var draftSelection: CGRect?
    private var draftAnnotation: ScreenshotAnnotation?
    private var textEditor: NSTextView?

    init(snapshot: ScreenSnapshot, overlay: ScreenshotOverlay) {
        self.snapshot = snapshot
        self.overlay = overlay
        let bounds = CGRect(origin: .zero, size: snapshot.screenFrame.size)
        container = NSView(frame: bounds)
        container.wantsLayer = true
        container.layer?.contents = snapshot.canvas.image
        container.layer?.contentsGravity = .resize
        container.layer?.magnificationFilter = .nearest
        super.init(frame: bounds)
        autoresizingMask = [.width, .height]
        container.addSubview(self)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var ownsSelection: Bool {
        overlay?.selectionView === self && overlay?.hasSelection == true
    }

    private var choosing: Bool {
        overlay?.hasSelection != true
    }

    // MARK: Pointer

    func pointerMoved(to point: CGPoint) {
        pointer = bounds.contains(point) ? point : nil
        refreshCursor()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(textEditor ?? self)
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        refreshCursor()
    }

    func refreshCursor() {
        guard let overlay, let pointer, ownsSelection, case .none = drag else {
            NSCursor.crosshair.set()
            return
        }
        let selection = overlay.selection
        if overlay.tool != nil, selection.contains(pointer) {
            (overlay.tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
        } else if let handle = ScreenshotGeometry.handle(at: pointer, in: selection) {
            Self.cursor(for: handle).set()
        } else if selection.contains(pointer) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private static func cursor(for handle: ScreenshotHandle) -> NSCursor {
        switch handle {
        case .left, .right: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        default: .crosshair
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let overlay else {
            return
        }
        let p = clamped(convert(event.locationInWindow, from: nil))
        if textEditor != nil {
            endTextEditing(commit: true)
            return
        }
        guard ownsSelection else {
            // A selection on another screen gives way unless it has marks.
            if overlay.hasSelection {
                guard overlay.annotations.isEmpty else {
                    return
                }
                overlay.clearSelection()
            }
            drag = .newSelection(start: p)
            return
        }
        let selection = overlay.selection
        if let tool = overlay.tool, selection.contains(p) {
            if tool == .text {
                beginTextEditing(at: p, style: overlay.style)
            } else {
                drag = .annotate(start: p)
                draftAnnotation = annotation(tool: tool, from: p, to: p, previous: nil)
            }
            return
        }
        if event.clickCount == 2, selection.contains(p) {
            overlay.finish(overlay.defaultAction)
            return
        }
        if let handle = ScreenshotGeometry.handle(at: p, in: selection) {
            drag = .resize(handle, original: selection)
        } else if selection.contains(p) {
            drag = .move(start: p, original: selection)
            NSCursor.closedHand.set()
        } else if overlay.annotations.isEmpty {
            overlay.clearSelection()
            drag = .newSelection(start: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let overlay else {
            return
        }
        let p = clamped(convert(event.locationInWindow, from: nil))
        pointer = p
        switch drag {
        case .none:
            return
        case .newSelection(let start):
            if hypot(p.x - start.x, p.y - start.y) >= ScreenshotGeometry.minimumDrag {
                draftSelection = ScreenshotGeometry.rect(from: start, to: p)
            }
        case .move(let start, let original):
            overlay.setToolbarHidden(true)
            overlay.updateSelection(ScreenshotGeometry.move(original, by: p.x - start.x, p.y - start.y, within: bounds))
        case .resize(let handle, let original):
            overlay.setToolbarHidden(true)
            overlay.updateSelection(ScreenshotGeometry.resize(original, handle: handle, to: p, bounds: bounds))
        case .annotate(let start):
            if let tool = overlay.tool {
                let inside = CGPoint(
                    x: min(max(p.x, overlay.selection.minX), overlay.selection.maxX),
                    y: min(max(p.y, overlay.selection.minY), overlay.selection.maxY)
                )
                draftAnnotation = annotation(tool: tool, from: start, to: inside, previous: draftAnnotation)
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let overlay else {
            return
        }
        let p = clamped(convert(event.locationInWindow, from: nil))
        let finished = drag
        drag = .none
        switch finished {
        case .none:
            break
        case .newSelection(let start):
            let rect = draftSelection ?? ScreenshotGeometry.window(at: start, in: snapshot.windowFrames, bounds: bounds)
            draftSelection = nil
            let aligned = ScreenshotGeometry.pixelAligned(rect, scale: snapshot.canvas.scale).intersection(bounds)
            if !aligned.isNull, aligned.width >= 2, aligned.height >= 2 {
                overlay.select(aligned, in: self)
            }
        case .move, .resize:
            let aligned = ScreenshotGeometry.pixelAligned(overlay.selection, scale: snapshot.canvas.scale).intersection(bounds)
            if aligned.width >= 2, aligned.height >= 2 {
                overlay.updateSelection(aligned)
            }
            overlay.setToolbarHidden(false)
        case .annotate:
            if let draft = draftAnnotation, Self.isVisible(draft) {
                overlay.add(draft)
            }
            draftAnnotation = nil
        }
        pointer = p
        refreshCursor()
        needsDisplay = true
    }

    /// Right click: drop the selection, or close the overlay when there is none.
    override func rightMouseDown(with event: NSEvent) {
        guard let overlay else {
            return
        }
        if overlay.hasSelection, overlay.mode.keepsSelection {
            overlay.clearSelection()
            pointerMoved(to: convert(event.locationInWindow, from: nil))
        } else {
            overlay.finish(.cancel)
        }
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    private func annotation(tool: ScreenshotTool, from start: CGPoint, to end: CGPoint, previous: ScreenshotAnnotation?) -> ScreenshotAnnotation {
        let style = overlay?.style ?? ScreenshotStyle()
        let rect = ScreenshotGeometry.rect(from: start, to: end)
        let shape: ScreenshotAnnotation.Shape
        switch tool {
        case .rectangle: shape = .rectangle(rect)
        case .ellipse: shape = .ellipse(rect)
        case .arrow: shape = .arrow(from: start, to: end)
        case .mosaic: shape = .mosaic(rect)
        case .text: shape = .text("", topLeft: start)
        case .pen:
            var points: [CGPoint] = []
            if case .pen(let previousPoints)? = previous?.shape {
                points = previousPoints
            }
            if let last = points.last, hypot(last.x - end.x, last.y - end.y) < 1 {
                return previous ?? ScreenshotAnnotation(shape: .pen(points), style: style)
            }
            points.append(end)
            shape = .pen(points)
        }
        return ScreenshotAnnotation(shape: shape, style: style)
    }

    private static func isVisible(_ annotation: ScreenshotAnnotation) -> Bool {
        switch annotation.shape {
        case .rectangle(let r), .ellipse(let r), .mosaic(let r): r.width >= 2 && r.height >= 2
        case .arrow(let from, let to): hypot(to.x - from.x, to.y - from.y) >= 4
        case .pen(let points): !points.isEmpty
        case .text(let text, _): !text.isEmpty
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let overlay else {
            return
        }
        switch event.keyCode {
        case 53:
            overlay.finish(.cancel)
        case 36, 76:
            if overlay.hasSelection {
                overlay.finish(overlay.defaultAction)
            }
        default:
            break
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let overlay, overlay.mode == .capture,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "c" where overlay.hasSelection && textEditor == nil:
            overlay.finish(.copy)
        case "s" where overlay.hasSelection:
            overlay.finish(.save)
        case "z" where textEditor == nil:
            overlay.undo()
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Text

    private func beginTextEditing(at p: CGPoint, style: ScreenshotStyle) {
        let font = ScreenshotAnnotation.font(for: style.size)
        let lineHeight = ScreenshotRenderer.attributedText("国A", style: style).size().height
        let editor = NSTextView(frame: CGRect(x: p.x, y: p.y - lineHeight / 2, width: 24, height: lineHeight))
        editor.delegate = self
        editor.font = font
        editor.textColor = NSColor(cgColor: style.color.cgColor)
        editor.insertionPointColor = NSColor(cgColor: style.color.cgColor) ?? .red
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: lineHeight)
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.minSize = CGSize(width: 24, height: lineHeight)
        editor.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: lineHeight)
        addSubview(editor)
        textEditor = editor
        window?.makeFirstResponder(editor)
        needsDisplay = true
    }

    func restyleTextEditing(_ style: ScreenshotStyle) {
        guard let editor = textEditor else {
            return
        }
        let top = editor.frame.maxY
        let lineHeight = ScreenshotRenderer.attributedText("国A", style: style).size().height
        editor.font = ScreenshotAnnotation.font(for: style.size)
        editor.textColor = NSColor(cgColor: style.color.cgColor)
        editor.insertionPointColor = NSColor(cgColor: style.color.cgColor) ?? .red
        editor.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: lineHeight)
        editor.minSize = CGSize(width: 24, height: lineHeight)
        editor.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: lineHeight)
        editor.frame = CGRect(x: editor.frame.minX, y: top - lineHeight, width: editor.frame.width, height: lineHeight)
        window?.makeFirstResponder(editor)
        needsDisplay = true
    }

    func endTextEditing(commit: Bool) {
        guard let editor = textEditor else {
            return
        }
        textEditor = nil
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let topLeft = CGPoint(x: editor.frame.minX, y: editor.frame.maxY)
        editor.removeFromSuperview()
        if commit, !text.isEmpty, let overlay {
            overlay.add(ScreenshotAnnotation(shape: .text(text, topLeft: topLeft), style: overlay.style))
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            endTextEditing(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endTextEditing(commit: false)
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay, let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        let selection: CGRect? = ownsSelection ? overlay.selection : draftSelection
        let hover: CGRect? = selection == nil && choosing && pointer != nil
            ? ScreenshotGeometry.window(at: pointer!, in: snapshot.windowFrames, bounds: bounds)
            : nil

        if let selection, ownsSelection {
            ctx.saveGState()
            ctx.clip(to: selection)
            ScreenshotRenderer.draw(overlay.annotations, in: ctx, canvas: snapshot.canvas)
            if let draftAnnotation {
                ScreenshotRenderer.draw(draftAnnotation, in: ctx, canvas: snapshot.canvas)
            }
            ctx.restoreGState()
        }

        ctx.setFillColor(Self.dimColor)
        ctx.addRect(bounds)
        if let clear = selection ?? hover {
            ctx.addRect(clear)
        }
        ctx.fillPath(using: .evenOdd)

        let accent = NSColor.controlAccentColor.cgColor
        if let hover {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(3)
            ctx.stroke(hover.insetBy(dx: 1.5, dy: 1.5))
        }
        if let selection {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5)
            ctx.stroke(selection.insetBy(dx: -0.75, dy: -0.75))
            if ownsSelection, overlay.mode.keepsSelection, case .none = drag {
                drawHandles(selection, in: ctx, accent: accent)
            }
            drawSizeLabel(for: selection)
        }
        if let editor = textEditor {
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(editor.frame.insetBy(dx: -4, dy: -3))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if choosing {
            switch overlay.mode {
            case .capture: break
            case .recognizeText: drawHint("Drag to select the text to recognize, or click to pick a window · Esc Cancel")
            case .record: drawHint("Drag to select the area to record, or click to pick a window · Esc Cancel")
            }
        }
        let showsMagnifier: Bool
        switch drag {
        case .none: showsMagnifier = choosing
        case .newSelection: showsMagnifier = true
        default: showsMagnifier = false
        }
        if showsMagnifier, let pointer {
            drawMagnifier(at: pointer, in: ctx)
        }
    }

    private func drawHandles(_ rect: CGRect, in ctx: CGContext, accent: CGColor) {
        for (_, point) in ScreenshotGeometry.handlePoints(for: rect) {
            let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: dot)
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: dot)
        }
    }

    private func drawSizeLabel(for selection: CGRect) {
        let scale = snapshot.canvas.scale
        let text = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
        drawLabel(text, at: { size in ScreenshotGeometry.sizeLabelOrigin(size: size, selection: selection, bounds: self.bounds) })
    }

    private func drawHint(_ text: String) {
        drawLabel(text, font: .systemFont(ofSize: 14, weight: .medium)) { size in
            CGPoint(x: self.bounds.midX - size.width / 2, y: self.bounds.maxY - size.height - 60)
        }
    }

    private func drawLabel(_ text: String, font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .medium), at origin: (CGSize) -> CGPoint) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let textSize = string.size()
        let size = CGSize(width: textSize.width + 14, height: textSize.height + 6)
        let rect = CGRect(origin: origin(size), size: size)
        NSColor(white: 0, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        string.draw(at: CGPoint(x: rect.minX + 7, y: rect.minY + 3))
    }

    /// A zoomed view of the pixels around the pointer, with the pointer's position and color.
    private func drawMagnifier(at p: CGPoint, in ctx: CGContext) {
        let scale = snapshot.canvas.scale
        let image = snapshot.canvas.image
        let count = Self.magnifierPixels
        let edge = CGFloat(count) * Self.magnifierZoom
        let infoHeight: CGFloat = 38
        let size = CGSize(width: edge, height: edge + infoHeight)
        let origin = ScreenshotGeometry.magnifierOrigin(size: size, cursor: p, bounds: bounds)
        let zoomRect = CGRect(x: origin.x, y: origin.y + infoHeight, width: edge, height: edge)

        let centerX = Int(p.x * scale), centerY = Int((bounds.height - p.y) * scale)
        let source = CGRect(x: centerX - count / 2, y: centerY - count / 2, width: count, height: count)
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(zoomRect)
        if let crop = image.cropping(to: source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))) {
            // Keep pixels in place at the screen's edges, where the crop is smaller than the grid.
            let visible = source.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let dx = (visible.minX - source.minX) * Self.magnifierZoom
            let dyTop = (visible.minY - source.minY) * Self.magnifierZoom
            let drawRect = CGRect(
                x: zoomRect.minX + dx, y: zoomRect.maxY - dyTop - visible.height * Self.magnifierZoom,
                width: visible.width * Self.magnifierZoom, height: visible.height * Self.magnifierZoom
            )
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: drawRect)
        }
        let cell = Self.magnifierZoom
        let center = CGRect(x: zoomRect.minX + CGFloat(count / 2) * cell, y: zoomRect.minY + CGFloat(count / 2) * cell, width: cell, height: cell)
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor)
        ctx.fill(CGRect(x: zoomRect.minX, y: center.minY, width: edge, height: cell))
        ctx.fill(CGRect(x: center.minX, y: zoomRect.minY, width: cell, height: edge))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(1)
        ctx.stroke(center)
        ctx.restoreGState()

        let infoRect = CGRect(x: origin.x, y: origin.y, width: edge, height: infoHeight)
        NSColor(white: 0, alpha: 0.78).setFill()
        infoRect.fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: CGRect(x: origin.x, y: origin.y, width: edge, height: edge + infoHeight).insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let lines = ["\(Int(p.x)), \(Int(bounds.height - p.y))", Self.hexColor(of: image, x: centerX, y: centerY) ?? ""]
        for (index, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.white])
                .draw(at: CGPoint(x: infoRect.minX + 8, y: infoRect.maxY - 17 - CGFloat(index) * 15))
        }
    }

    static func hexColor(of image: CGImage, x: Int, y: Int) -> String? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]) : nil
    }
}

/// Tools, undo, and the finishing actions in one row; sizes and colors in a second row while a
/// marking tool is chosen.
final class ScreenshotToolbar: NSView {
    var onTool: ((ScreenshotTool?) -> Void)?
    var onStyle: ((ScreenshotStyle) -> Void)?
    var onUndo: (() -> Void)?
    var onAction: ((ScreenshotOverlay.Action) -> Void)?

    private let background = NSVisualEffectView()
    private let rows = NSStackView()
    private let mainRow = NSStackView()
    private let styleRow = NSStackView()
    private var toolButtons: [(ScreenshotTool, NSButton)] = []
    private var sizeButtons: [(ScreenshotStrokeSize, NSButton)] = []
    private var colorButtons: [(ScreenshotColor, NSButton)] = []
    private var colorSeparator: NSView?
    private var undoButton: NSButton?
    private var style = ScreenshotStyle()

    /// With `recording`, only cancel and start recording; otherwise the marking tools and every action.
    init(recording: Bool = false) {
        super.init(frame: .zero)
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.maskImage = CandidatePanel.roundedMask(radius: 8)
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        if recording {
            let cancel = Self.button(symbol: "xmark", tip: "Cancel Esc", target: self, action: #selector(actionClicked(_:)))
            cancel.tag = Self.tag(for: .cancel)
            mainRow.addArrangedSubview(cancel)
            let start = Self.button(symbol: "record.circle", tip: "Start recording ⏎", target: self, action: #selector(actionClicked(_:)))
            start.tag = Self.tag(for: .record)
            start.contentTintColor = .systemRed
            mainRow.addArrangedSubview(start)
        } else {
            addCaptureButtons()
        }

        for size in ScreenshotStrokeSize.allCases {
            let button = Self.button(image: Self.dotImage(diameter: 3 + CGFloat(sizeIndex(size)) * 4), tip: "Size", target: self, action: #selector(sizeClicked(_:)))
            sizeButtons.append((size, button))
            styleRow.addArrangedSubview(button)
        }
        let separator = Self.separator()
        colorSeparator = separator
        styleRow.addArrangedSubview(separator)
        for color in ScreenshotColor.allCases {
            let button = Self.button(image: nil, tip: "Color", target: self, action: #selector(colorClicked(_:)))
            colorButtons.append((color, button))
            styleRow.addArrangedSubview(button)
        }

        for row in [mainRow, styleRow] {
            row.orientation = .horizontal
            row.spacing = 2
        }
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        rows.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        rows.addArrangedSubview(mainRow)
        rows.addArrangedSubview(styleRow)
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update(tool: nil, style: style, canUndo: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func addCaptureButtons() {
        for tool in ScreenshotTool.allCases {
            let button = Self.button(symbol: tool.symbolName, tip: tool.title, target: self, action: #selector(toolClicked(_:)))
            toolButtons.append((tool, button))
            mainRow.addArrangedSubview(button)
        }
        mainRow.addArrangedSubview(Self.separator())
        let undo = Self.button(symbol: "arrow.uturn.backward", tip: "Undo ⌘Z", target: self, action: #selector(undoClicked))
        undoButton = undo
        mainRow.addArrangedSubview(undo)
        mainRow.addArrangedSubview(Self.separator())
        let actions: [(String, String, ScreenshotOverlay.Action)] = [
            ("text.viewfinder", "Recognize text and copy", .recognizeText),
            ("pin", "Pin to screen", .pin),
            ("record.circle", "Record this area (marks are not recorded)", .record),
            ("square.and.arrow.down", "Save ⌘S", .save),
        ]
        for (symbol, tip, action) in actions {
            let button = Self.button(symbol: symbol, tip: tip, target: self, action: #selector(actionClicked(_:)))
            button.tag = Self.tag(for: action)
            mainRow.addArrangedSubview(button)
        }
        mainRow.addArrangedSubview(Self.separator())
        let cancel = Self.button(symbol: "xmark", tip: "Cancel Esc", target: self, action: #selector(actionClicked(_:)))
        cancel.tag = Self.tag(for: .cancel)
        cancel.contentTintColor = .systemRed
        mainRow.addArrangedSubview(cancel)
        let done = Self.button(symbol: "checkmark", tip: "Copy ⏎ / ⌘C", target: self, action: #selector(actionClicked(_:)))
        done.tag = Self.tag(for: .copy)
        done.contentTintColor = .systemGreen
        mainRow.addArrangedSubview(done)
    }

    /// Clicks on the toolbar must not reach the overlay under it.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    func update(tool: ScreenshotTool?, style: ScreenshotStyle, canUndo: Bool) {
        self.style = style
        for (candidate, button) in toolButtons {
            Self.setSelected(button, candidate == tool)
        }
        undoButton?.isEnabled = canUndo
        styleRow.isHidden = tool == nil
        let showsColors = tool?.usesColor ?? false
        colorSeparator?.isHidden = !showsColors
        for (size, button) in sizeButtons {
            Self.setSelected(button, size == style.size)
        }
        for (color, button) in colorButtons {
            button.isHidden = !showsColors
            button.image = Self.swatchImage(color, selected: color == style.color)
        }
        layoutSubtreeIfNeeded()
    }

    private func sizeIndex(_ size: ScreenshotStrokeSize) -> Int {
        ScreenshotStrokeSize.allCases.firstIndex(of: size) ?? 0
    }

    @objc private func toolClicked(_ sender: NSButton) {
        onTool?(toolButtons.first { $0.1 === sender }?.0)
    }

    @objc private func undoClicked() {
        onUndo?()
    }

    @objc private func actionClicked(_ sender: NSButton) {
        if let action = Self.action(forTag: sender.tag) {
            onAction?(action)
        }
    }

    @objc private func sizeClicked(_ sender: NSButton) {
        guard let size = sizeButtons.first(where: { $0.1 === sender })?.0 else {
            return
        }
        var next = style
        next.size = size
        onStyle?(next)
    }

    @objc private func colorClicked(_ sender: NSButton) {
        guard let color = colorButtons.first(where: { $0.1 === sender })?.0 else {
            return
        }
        var next = style
        next.color = color
        onStyle?(next)
    }

    private static let actionOrder: [ScreenshotOverlay.Action] = [.copy, .save, .pin, .recognizeText, .record, .cancel]

    private static func tag(for action: ScreenshotOverlay.Action) -> Int {
        (actionOrder.firstIndex(of: action) ?? 0) + 1
    }

    private static func action(forTag tag: Int) -> ScreenshotOverlay.Action? {
        actionOrder.indices.contains(tag - 1) ? actionOrder[tag - 1] : nil
    }

    private static func button(symbol: String, tip: String, target: AnyObject, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        return button(image: image, tip: tip, target: target, action: action)
    }

    private static func button(image: NSImage?, tip: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.image = image
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.toolTip = tip
        button.target = target
        button.action = action
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        return button
    }

    private static func setSelected(_ button: NSButton, _ selected: Bool) {
        button.contentTintColor = selected ? .controlAccentColor : nil
        button.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : nil
    }

    private static func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 18),
        ])
        return line
    }

    private static func dotImage(diameter: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func swatchImage(_ color: ScreenshotColor, selected: Bool) -> NSImage {
        NSImage(size: CGSize(width: 18, height: 18), flipped: false) { rect in
            let fill = NSColor(cgColor: color.cgColor) ?? .red
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                NSColor.controlAccentColor.setStroke()
                ring.stroke()
            }
            return true
        }
    }
}
