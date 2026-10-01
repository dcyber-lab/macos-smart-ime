import AppKit

/// Popup near the selection for selection translation; styled like the candidate panel.
@MainActor
final class TranslationPopup {
    static let shared = TranslationPopup()

    private let window: NSPanel
    private let contentView = TranslationPopupView()
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
        background.maskImage = CandidatePanel.roundedMask(radius: CandidatePanel.cornerRadius)
        background.addSubview(contentView)
        window.contentView = background
    }

    func show(_ state: SelectionTranslationController.State, caretRect reportedCaretRect: CGRect) {
        guard contentView.configure(for: state) else {
            hide()
            return
        }
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
        window.orderOut(nil)
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
            fill(badge: direction.label, source: source, body: "翻译中…", hint: "Esc 取消")
        case .result(let source, let translation, let direction):
            fill(badge: direction.label, source: source, body: translation, hint: "⏎ 替换 · Esc 取消")
        case .message(let text):
            fill(badge: "翻译", source: "", body: text, hint: "Esc 关闭")
        }
        layoutSubtreeIfNeeded()
        return true
    }

    private func fill(badge text: String, source: String, body: String, hint: String) {
        badge.text = text
        sourceLabel.stringValue = source
        bodyLabel.stringValue = body
        hintLabel.stringValue = hint
    }
}

/// Small capsule label, drawn like the candidate panel's 英/译 tags.
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
