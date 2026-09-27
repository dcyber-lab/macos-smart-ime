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

/// Source line, wrapping translation (or message), and key hint.
final class TranslationPopupView: NSView {
    private static let maxTextWidth: CGFloat = 400
    private static let minimumWidth: CGFloat = 180
    private static let insets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

    private let sourceLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let stack: NSStackView

    override init(frame frameRect: NSRect) {
        stack = NSStackView(views: [sourceLabel, bodyLabel, hintLabel])
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

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = Self.insets
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxTextWidth),
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
            fill(title: "\(direction.label)  \(source)", body: "翻译中…", hint: "Esc 取消")
        case .result(let source, let translation, let direction):
            fill(title: "\(direction.label)  \(source)", body: translation, hint: "⏎ 替换 · Esc 取消")
        case .message(let text):
            fill(title: "翻译", body: text, hint: "Esc 关闭")
        }
        layoutSubtreeIfNeeded()
        return true
    }

    private func fill(title: String, body: String, hint: String) {
        sourceLabel.stringValue = title
        bodyLabel.stringValue = body
        hintLabel.stringValue = hint
    }
}
