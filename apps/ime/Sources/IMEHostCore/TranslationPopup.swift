import AppKit

/// Popup near the selection for selection translation; styled like the candidate panel.
@MainActor
final class TranslationPopup {
    static let shared = TranslationPopup()

    private let window: PopupPanel
    private let contentView = TranslationPopupView()
    private var lastCaretRect: CGRect?
    /// Receives key codes while the popup is the key window (read-only mode, where no text field forwards keys).
    var keyHandler: ((UInt16) -> Void)? {
        didSet { window.onKey = keyHandler }
    }
    var dismissHandler: (() -> Void)? {
        didSet { window.onDismiss = dismissHandler }
    }

    private init() {
        window = PopupPanel(
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
        background.maskImage = CandidatePanel.roundedMask(radius: CandidatePanel.cornerRadius)
        background.addSubview(contentView)
        window.contentView = background
    }

    func show(_ state: SelectionTranslationController.State, caretRect reportedCaretRect: CGRect) {
        guard contentView.configure(for: state) else {
            hide()
            return
        }
        place(near: reportedCaretRect)
    }

    /// The AI rewrite popup in the same style: badge and source line, body, key hint.
    func show(_ state: AIRewriteController.State, caretRect reportedCaretRect: CGRect, readOnly: Bool = false) {
        guard let content = Self.content(for: state, readOnly: readOnly) else {
            hide()
            return
        }
        window.acceptsKeys = readOnly
        contentView.configure(badge: content.badge, source: content.source, body: content.body, hint: content.hint)
        place(near: reportedCaretRect)
        if readOnly {
            // An accessory app must be active for its panel to take the keyboard from the app in front.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func content(for state: AIRewriteController.State, readOnly: Bool = false) -> (badge: String, source: String, body: String, hint: String)? {
        switch state {
        case .idle:
            return nil
        case .choosing(let text, let defaultAction, let truncated):
            // Two even rows; a long row wrapped at whatever width the popup happened to have.
            let labels = AIAction.allCases.enumerated().map { "\($0.offset + 1) \($0.element.title)" }
            let split = (labels.count + 1) / 2
            let actions = [labels[..<split], labels[split...]].map { $0.joined(separator: "    ") }.joined(separator: "\n")
            let note = truncated ? " · Only the end of this line was read; select long messages first" : ""
            return ("✨ AI Rewrite", text, actions, "Number to choose · ⏎ \(defaultAction.title) · Esc Cancel\(note)")
        case .running(let action, let text):
            return ("✨ \(action.title)", text, "Generating…", "Esc Cancel")
        case .result(let action, let original, let rewritten):
            return ("✨ \(action.title)", original, rewritten, readOnly ? "⏎ Copy · Esc or click to close" : action == .explain ? "Esc Close" : "⏎ Replace · Esc Cancel")
        case .message(let text):
            return ("✨ AI Rewrite", "", text, "Esc Close")
        }
    }

    private func place(near reportedCaretRect: CGRect) {
        let size = contentView.fittingSize
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
        contentView.frame = CGRect(origin: .zero, size: size)
        window.invalidateShadow()
        window.orderFrontRegardless()
    }

    func hide() {
        window.acceptsKeys = false
        window.orderOut(nil)
    }
}

/// A non-activating panel that can take the keyboard when asked, so a popup over a web page gets its keys.
final class PopupPanel: NSPanel {
    var acceptsKeys = false
    var onKey: ((UInt16) -> Void)?
    /// A click on the popup, or the popup losing the keyboard (a click elsewhere): read-only popups close.
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeys }

    override func sendEvent(_ event: NSEvent) {
        if acceptsKeys, event.type == .leftMouseDown {
            onDismiss?()
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        if acceptsKeys {
            onDismiss?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if let onKey {
            onKey(event.keyCode)
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Direction badge and source line, wrapping translation (or message), and key hint.
final class TranslationPopupView: NSView {
    private static let maxTextWidth: CGFloat = 400
    private static let minimumWidth: CGFloat = 180
    private static let insets = NSEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)
    private static let badgeGap: CGFloat = 6
    private static let lineSpacing: CGFloat = 7

    private let badge = CapsuleBadgeView()
    private let sourceLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        sourceLabel.font = .systemFont(ofSize: 12)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.maximumNumberOfLines = 1
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textColor = .labelColor
        bodyLabel.preferredMaxLayoutWidth = Self.maxTextWidth
        bodyLabel.maximumNumberOfLines = 16
        bodyLabel.cell?.truncatesLastVisibleLine = true
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor

        let insets = Self.insets
        for view in [badge, sourceLabel, bodyLabel, hintLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // Each line is pinned on the left and only bounds the width on the right, so the
        // fitting width is the widest line plus both insets.
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            sourceLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: Self.badgeGap),
            sourceLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxTextWidth),
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            bodyLabel.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: Self.lineSpacing),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            hintLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: Self.lineSpacing),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
            trailingAnchor.constraint(greaterThanOrEqualTo: sourceLabel.trailingAnchor, constant: insets.right),
            trailingAnchor.constraint(greaterThanOrEqualTo: bodyLabel.trailingAnchor, constant: insets.right),
            trailingAnchor.constraint(greaterThanOrEqualTo: hintLabel.trailingAnchor, constant: insets.right),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Returns false for `.idle`, which has nothing to show.
    @discardableResult
    func configure(for state: SelectionTranslationController.State) -> Bool {
        switch state {
        case .idle:
            return false
        case .translating(let source, let direction):
            fill(badge: direction.label, source: source, body: "Translating…", hint: "Esc Cancel")
        case .result(let source, let translation, let direction):
            fill(badge: direction.label, source: source, body: translation, hint: "⏎ Replace · Esc Cancel")
        case .message(let text):
            fill(badge: "Translation", source: "", body: text, hint: "Esc Close")
        }
        layoutSubtreeIfNeeded()
        return true
    }

    func configure(badge: String, source: String, body: String, hint: String) {
        fill(badge: badge, source: source, body: body, hint: hint)
        layoutSubtreeIfNeeded()
    }

    private func fill(badge text: String, source: String, body: String, hint: String) {
        badge.text = text
        // The source is a one-line preview: line breaks would draw over the rows below it.
        sourceLabel.stringValue = source.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        bodyLabel.stringValue = body
        hintLabel.stringValue = hint
    }
}

/// Small capsule label, drawn like the candidate panel's EN/TR tags.
final class CapsuleBadgeView: NSView {
    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let padding = NSSize(width: 7, height: 2)

    var text = "" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = text.size(withAttributes: [.font: Self.font])
        return NSSize(width: ceil(size.width) + Self.padding.width * 2, height: ceil(size.height) + Self.padding.height * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: Self.padding.width, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}
