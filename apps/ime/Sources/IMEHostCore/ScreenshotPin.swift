import AppKit

/// A capture floating above other windows for reference. Drag to move, scroll or pinch to zoom,
/// double-click or Esc to close; the right-click menu copies, saves, or recognizes its text.
@MainActor
enum ScreenshotPin {
    private static var panels: [PinnedScreenshotPanel] = []

    static func show(image: CGImage, scale: CGFloat, screenRect: CGRect) {
        let panel = PinnedScreenshotPanel(image: image, scale: scale, frame: screenRect)
        panel.onClose = { [weak panel] in
            panels.removeAll { $0 === panel }
        }
        panels.append(panel)
        panel.orderFrontRegardless()
    }
}

final class PinnedScreenshotPanel: NSPanel {
    var onClose: (() -> Void)?
    let image: CGImage
    let scale: CGFloat
    private let baseSize: CGSize
    private var zoom: CGFloat = 1

    init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image
        self.scale = scale
        baseSize = frame.size
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary]
        contentView = PinnedScreenshotView(panel: self)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "c": copyImage()
        case "s": saveImage()
        case "w": close()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }

    /// Zooms about `anchor` (window coordinates), between 20% and 400%.
    func zoom(by factor: CGFloat, about anchor: CGPoint) {
        let next = min(max(zoom * factor, 0.2), 4)
        guard next != zoom else {
            return
        }
        let ratio = next / zoom
        zoom = next
        let old = frame
        let size = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        let origin = CGPoint(x: old.minX + anchor.x - anchor.x * ratio, y: old.minY + anchor.y - anchor.y * ratio)
        setFrame(CGRect(origin: origin, size: size), display: true)
    }

    @objc func copyImage() {
        ScreenshotService.copy(image: image, scale: scale)
        ScreenshotToast.show("Screenshot copied")
    }

    @objc func saveImage() {
        ScreenshotService.save(image: image, scale: scale)
    }

    @objc func recognizeText() {
        ScreenshotService.shared.recognizeAndCopy(image)
    }

    @objc func closePin() {
        close()
    }
}

private final class PinnedScreenshotView: NSView {
    private weak var panel: PinnedScreenshotPanel?

    init(panel: PinnedScreenshotPanel) {
        self.panel = panel
        super.init(frame: CGRect(origin: .zero, size: panel.frame.size))
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.contents = panel.image
        layer?.contentsGravity = .resize
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            panel?.close()
            return
        }
        panel?.makeKey()
        panel?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard delta != 0 else {
            return
        }
        panel?.zoom(by: 1 + delta / 200, about: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        panel?.zoom(by: 1 + event.magnification, about: convert(event.locationInWindow, from: nil))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let panel else {
            return nil
        }
        let menu = NSMenu()
        for (title, action, key) in [
            ("Copy", #selector(PinnedScreenshotPanel.copyImage), "c"),
            ("Save", #selector(PinnedScreenshotPanel.saveImage), "s"),
            ("Recognize Text and Copy", #selector(PinnedScreenshotPanel.recognizeText), ""),
            ("Close", #selector(PinnedScreenshotPanel.closePin), "w"),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = panel
            menu.addItem(item)
        }
        return menu
    }
}

/// A short message near the pointer that fades on its own and never takes clicks.
@MainActor
enum ScreenshotToast {
    private static var panel: NSPanel?
    private static var generation = 0

    static func show(_ text: String, duration: TimeInterval = 1.6) {
        let panel = panel ?? makePanel()
        self.panel = panel
        guard let label = panel.contentView?.subviews.first?.subviews.first as? NSTextField else {
            return
        }
        label.stringValue = text
        let textSize = label.fittingSize
        let size = CGSize(width: min(textSize.width, 420) + 28, height: textSize.height + 16)
        label.frame = CGRect(x: 14, y: 8, width: size.width - 28, height: textSize.height)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        var origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - 36 - size.height)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        generation += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            MainActor.assumeIsolated {
                guard current == generation else {
                    return
                }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        if current == generation {
                            panel.orderOut(nil)
                        }
                    }
                })
            }
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.maskImage = CandidatePanel.roundedMask(radius: 10)
        background.autoresizingMask = [.width, .height]
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = 420
        background.addSubview(label)
        panel.contentView = background
        return panel
    }
}
