import AppKit
import ImageIO

/// What the clipboard panel shows: a search field, the matches, and a preview of the chosen one.
@MainActor
final class ClipboardPanelModel {
    var query = "" {
        didSet { reload() }
    }
    private(set) var results: [ClipboardItem] = []
    /// Bumped whenever `results` is replaced, so the list reloads only then.
    private(set) var resultsVersion = 0
    var selection = 0 {
        didSet {
            prefetchNeighbors()
            onChange()
        }
    }

    let store: ClipboardHistoryStore
    var onChoose: (ClipboardItem) -> Void = { _ in }
    /// After the results or the selection change, and when a thumbnail finishes decoding.
    var onChange: () -> Void = {}

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    var selected: ClipboardItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    private let previews = NSCache<NSUUID, NSImage>()
    private var loading: Set<UUID> = []

    private struct DecodedImage: @unchecked Sendable {
        let cgImage: CGImage
    }

    /// A screen-sized copy of the image, decoded once per entry: decoding the full file on every
    /// selection change made ↑↓ stutter. Not decoded yet: nil now, and `onChange` runs when it is.
    func previewImage(for item: ClipboardItem) -> NSImage? {
        if let cached = previews.object(forKey: item.id as NSUUID) {
            return cached
        }
        load(item)
        return nil
    }

    /// Decodes the images next to the selection in the background, so stepping onto one is instant.
    func prefetchNeighbors() {
        for index in (selection - 3)...(selection + 3) where results.indices.contains(index) && results[index].kind == .image {
            load(results[index])
        }
    }

    private func load(_ item: ClipboardItem) {
        guard item.kind == .image, previews.object(forKey: item.id as NSUUID) == nil, !loading.contains(item.id),
              let url = store.imageURL(for: item)
        else {
            return
        }
        loading.insert(item.id)
        let id = item.id
        Task.detached(priority: .userInitiated) { [weak self] in
            let decoded = Self.decode(url)
            await MainActor.run {
                guard let self else {
                    return
                }
                self.loading.remove(id)
                if let decoded {
                    let cg = decoded.cgImage
                    self.previews.setObject(NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)), forKey: id as NSUUID)
                    self.onChange()
                }
            }
        }
    }

    nonisolated private static func decode(_ url: URL) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1200,
              ] as CFDictionary)
        else {
            return nil
        }
        return DecodedImage(cgImage: cg)
    }

    /// The only place `results` changes; setting `selection` afterwards tells the view.
    func reload() {
        results = store.search(query)
        resultsVersion += 1
        selection = min(selection, max(0, results.count - 1))
    }

    func reset() {
        query = ""
        selection = 0
        reload()
    }

    func move(_ delta: Int) {
        let target = min(max(selection + delta, 0), results.count - 1)
        // Holding ↓ on the last row repeats the key; nothing needs redrawing then.
        guard !results.isEmpty, target != selection else {
            return
        }
        selection = target
    }

    func choose(at index: Int) {
        guard results.indices.contains(index) else {
            return
        }
        onChoose(results[index])
    }

    func togglePinSelected() {
        guard let item = selected else {
            return
        }
        store.togglePin(item)
        reload()
    }

    func removeSelected() {
        guard let item = selected else {
            return
        }
        store.remove(item)
        reload()
    }
}

/// Alfred-style history panel: keys go to the search field; ↑↓ move, ⏎ or ⌘1–9 choose, ⌘P pins, ⌘⌫
/// deletes, Esc closes. The input method is activated while it shows: an accessory app's window does not take
/// the keyboard otherwise, and the app in front kept moving its caret with every ↑↓. Closing hands it back.
@MainActor
final class ClipboardPanel: NSPanel {
    static let size = CGSize(width: 760, height: 440)

    private let model: ClipboardPanelModel
    private let content: ClipboardPanelContentView
    private var monitor: Any?
    private var previousApp: NSRunningApplication?
    private var resigning = false
    private let keyStats = ArrowKeyStats()

    init(store: ClipboardHistoryStore, onChoose: @escaping (ClipboardItem) -> Void) {
        model = ClipboardPanelModel(store: store)
        content = ClipboardPanelContentView(model: model)
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        model.onChoose = { [weak self] item in
            self?.close()
            onChoose(item)
        }
        let background: NSView
        // `defaults write lab.dcyber.inputmethod.smartime ClipboardPanelBlur -bool false` swaps the blur for a
        // solid background, to tell a rendering cost from a key-handling one.
        if UserDefaults.standard.object(forKey: "ClipboardPanelBlur") as? Bool ?? true {
            let blur = NSVisualEffectView(frame: CGRect(origin: .zero, size: Self.size))
            blur.material = .popover
            blur.state = .active
            blur.blendingMode = .behindWindow
            blur.maskImage = CandidatePanel.roundedMask(radius: 14)
            background = blur
        } else {
            background = NSView(frame: CGRect(origin: .zero, size: Self.size))
            background.wantsLayer = true
            background.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            background.layer?.cornerRadius = 14
        }
        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        background.addSubview(content)
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    func show() {
        keyStats.start()
        model.reset()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: Self.size)
        setFrameOrigin(CGPoint(x: visible.midX - Self.size.width / 2, y: visible.midY - Self.size.height / 2 + visible.height * 0.12))
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != .current {
            previousApp = frontmost
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        content.focusSearch()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    override func close() {
        if let summary = keyStats.stop() {
            AIAssistEventLog.shared.append(summary, app: "clipboard")
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        super.close()
        // After a click in another app, that app is the one to keep.
        if !resigning {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }

    /// A click in another app takes the keyboard away.
    override func resignKey() {
        super.resignKey()
        if isVisible {
            resigning = true
            close()
            resigning = false
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === self else {
            return false
        }
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if event.keyCode == 125 || event.keyCode == 126 {
            keyStats.arrow(event)
        }
        switch event.keyCode {
        case 53: close()
        case 126: model.move(-1)
        case 125: model.move(1)
        case 36, 76: model.choose(at: model.selection)
        case 51 where command: model.removeSelected()
        default:
            guard command, let characters = event.charactersIgnoringModifiers else {
                return false
            }
            if characters == "p" {
                model.togglePinSelected()
            } else if let digit = Int(characters), (1...9).contains(digit) {
                model.choose(at: digit - 1)
            } else {
                return false
            }
        }
        return true
    }
}

/// How ↑↓ behaved while the panel was open, for the event log. Most of a key's cost comes after `handle`
/// returns, when views lay out and Core Animation commits before the run loop sleeps, so the main thread is
/// timed per run-loop turn and each turn within 250 ms of an arrow is charged to it.
@MainActor
private final class ArrowKeyStats {
    private var ages: [Double] = []
    private var gaps: [Double] = []
    private var work: [Double] = []
    private var latency: [Double] = []
    private var longestTurn = 0.0
    private var current: (stamp: TimeInterval, work: Double, lastCommit: TimeInterval?)?
    private var lastStamp: TimeInterval?
    private var turnStart = ProcessInfo.processInfo.systemUptime
    private var observers: [CFRunLoopObserver] = []

    func start() {
        _ = stop()
        gaps = []
        work = []
        latency = []
        longestTurn = 0
        lastStamp = nil
        turnStart = ProcessInfo.processInfo.systemUptime
        // First after the run loop wakes, last before it sleeps (after the Core Animation commit).
        let woke = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.turnStart = ProcessInfo.processInfo.systemUptime }
        }
        let sleeps = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.turnEnded() }
        }
        observers = [woke, sleeps].compactMap { $0 }
        for observer in observers {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    func arrow(_ event: NSEvent) {
        finishKey()
        ages.append((ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000)
        if let lastStamp {
            gaps.append((event.timestamp - lastStamp) * 1000)
        }
        lastStamp = event.timestamp
        current = (event.timestamp, 0, nil)
    }

    /// The summary line once per opening, or nil when fewer than two arrows were pressed.
    func stop() -> String? {
        finishKey()
        for observer in observers {
            CFRunLoopObserverInvalidate(observer)
        }
        observers = []
        defer { ages = [] }
        guard ages.count > 1 else {
            return nil
        }
        return String(
            format: "clipboard panel: %d arrows, gap avg %.0f ms, event age avg %.1f max %.1f ms, main-thread work per arrow %@, key to last commit %@, longest turn %.1f ms",
            ages.count, gaps.reduce(0, +) / Double(max(gaps.count, 1)), ages.reduce(0, +) / Double(ages.count), ages.max() ?? 0,
            Self.percentiles(work), Self.percentiles(latency), longestTurn
        )
    }

    private func turnEnded() {
        let now = ProcessInfo.processInfo.systemUptime
        let busy = (now - turnStart) * 1000
        turnStart = now
        longestTurn = max(longestTurn, busy)
        guard var key = current, now - key.stamp < 0.25 else {
            return
        }
        key.work += busy
        if busy > 0.5 {
            key.lastCommit = now
        }
        current = key
    }

    private func finishKey() {
        guard let key = current else {
            return
        }
        current = nil
        work.append(key.work)
        if let lastCommit = key.lastCommit {
            latency.append((lastCommit - key.stamp) * 1000)
        }
    }

    private static func percentiles(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard let max = sorted.last else {
            return "n/a"
        }
        return String(format: "p50 %.1f p90 %.1f max %.1f ms", sorted[sorted.count / 2], sorted[sorted.count * 9 / 10], max)
    }
}

// MARK: - Views

/// The panel's content, in AppKit. The SwiftUI version laid the whole panel out again on every ↑↓: 5–12 ms a
/// step on an M4 Pro with spikes past 30 ms, measured on a standalone copy, while the same list with no
/// preview took about 1 ms. A step here selects a table row and changes what the preview shows.
private final class ClipboardPanelContentView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Metrics {
        static let listWidth: CGFloat = 360
        static let listPadding: CGFloat = 8
        static let rowHeight: CGFloat = 36
        static let rowSpacing: CGFloat = 2
        static let searchHorizontalPadding: CGFloat = 18
        static let searchVerticalPadding: CGFloat = 14
        static let hintVerticalPadding: CGFloat = 7
    }

    private let model: ClipboardPanelModel
    private let searchField = NSTextField()
    private let table = NSTableView()
    private let listScroll = NSScrollView()
    private let preview = ClipboardPreviewView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "↑↓ Select · ⏎ Paste · ⌘1–9 Paste directly · ⌘P Pin · ⌘⌫ Delete · Esc Close")
    private let topLine = NSBox()
    private let middleLine = NSBox()
    private let bottomLine = NSBox()
    private var shownVersion = -1

    init(model: ClipboardPanelModel) {
        self.model = model
        super.init(frame: .zero)
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 22)
        searchField.placeholderString = "Search clipboard history"
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.delegate = self

        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.rowHeight = Metrics.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: Metrics.rowSpacing)
        // The search field keeps the keyboard; a click still selects.
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(chooseClickedRow)
        listScroll.documentView = table
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true

        emptyLabel.textColor = .secondaryLabelColor
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        for line in [topLine, middleLine, bottomLine] {
            line.boxType = .separator
        }
        for view in [searchField, topLine, listScroll, middleLine, preview, emptyLabel, bottomLine, hintLabel] {
            addSubview(view)
        }
        model.onChange = { [weak self] in
            self?.refresh()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    private func refresh() {
        let isEmpty = model.results.isEmpty
        if searchField.stringValue != model.query {
            searchField.stringValue = model.query
        }
        if shownVersion != model.resultsVersion {
            shownVersion = model.resultsVersion
            table.reloadData()
            listScroll.isHidden = isEmpty
            middleLine.isHidden = isEmpty
            preview.isHidden = isEmpty
            emptyLabel.isHidden = !isEmpty
            emptyLabel.stringValue = model.query.isEmpty ? "Nothing copied yet" : "No matches"
            needsLayout = true
        }
        if !isEmpty, table.selectedRow != model.selection {
            table.selectRowIndexes(IndexSet(integer: model.selection), byExtendingSelection: false)
            table.scrollRowToVisible(model.selection)
        }
        let item = model.selected
        if preview.itemID != item?.id {
            preview.show(item)
        }
        // Runs again when a thumbnail finishes decoding.
        if let item, item.kind == .image {
            let image = model.previewImage(for: item)
            preview.showImage(image, missing: image == nil && model.store.imageURL(for: item).map { FileManager.default.fileExists(atPath: $0.path) } != true)
        }
    }

    @objc private func chooseClickedRow() {
        model.choose(at: table.clickedRow)
    }

    override func layout() {
        super.layout()
        let searchHeight = searchField.intrinsicContentSize.height
        searchField.frame = CGRect(
            x: Metrics.searchHorizontalPadding, y: Metrics.searchVerticalPadding,
            width: bounds.width - Metrics.searchHorizontalPadding * 2, height: searchHeight
        )
        let top = searchHeight + Metrics.searchVerticalPadding * 2
        topLine.frame = CGRect(x: 0, y: top, width: bounds.width, height: 1)
        let hintHeight = hintLabel.intrinsicContentSize.height
        let bottom = bounds.height - hintHeight - Metrics.hintVerticalPadding * 2
        bottomLine.frame = CGRect(x: 0, y: bottom - 1, width: bounds.width, height: 1)
        hintLabel.frame = CGRect(x: 0, y: bottom + Metrics.hintVerticalPadding, width: bounds.width, height: hintHeight)

        let middle = CGRect(x: 0, y: top + 1, width: bounds.width, height: max(0, bottom - 1 - (top + 1)))
        listScroll.frame = middle.divided(atDistance: Metrics.listWidth, from: .minXEdge).slice.insetBy(dx: Metrics.listPadding, dy: Metrics.listPadding)
        table.tableColumns.first?.width = listScroll.contentSize.width
        middleLine.frame = CGRect(x: Metrics.listWidth, y: middle.minY, width: 1, height: middle.height)
        preview.frame = CGRect(x: Metrics.listWidth + 1, y: middle.minY, width: max(0, middle.width - Metrics.listWidth - 1), height: middle.height)
        let empty = emptyLabel.intrinsicContentSize
        emptyLabel.frame = CGRect(x: middle.midX - empty.width / 2, y: middle.midY - empty.height / 2, width: empty.width, height: empty.height)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ClipboardCellView.identifier, owner: nil) as? ClipboardCellView ?? ClipboardCellView()
        let item = model.results[row]
        cell.configure(item, index: row, isPinned: model.store.isPinned(item))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipboardRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        if row >= 0, row != model.selection {
            model.selection = row
        }
    }

    // MARK: Search

    func controlTextDidChange(_ notification: Notification) {
        model.query = searchField.stringValue
    }
}

/// An accent-filled rounded selection, also while the input method is not the active app (it never is).
private final class ClipboardRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

/// App icon, first line, pin, and ⌘1–9.
private final class ClipboardCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ClipboardCell")
    private static let spacing: CGFloat = 10
    private static let iconSize: CGFloat = 24

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let pin = NSImageView()
    private let shortcut = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        title.font = .systemFont(ofSize: 15)
        title.lineBreakMode = .byTruncatingTail
        shortcut.font = .systemFont(ofSize: 15)
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pin.symbolConfiguration = NSImage.SymbolConfiguration(textStyle: .caption1)
        for view in [icon, title, pin, shortcut] {
            addSubview(view)
        }
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(_ item: ClipboardItem, index: Int, isPinned: Bool) {
        icon.image = AppIcons.icon(for: item.appBundleID)
        title.stringValue = item.title
        pin.isHidden = !isPinned
        shortcut.stringValue = "⌘\(index + 1)"
        shortcut.isHidden = index >= 9
        needsLayout = true
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }

    private func applyColors() {
        let selected = backgroundStyle == .emphasized
        title.textColor = selected ? .white : .labelColor
        shortcut.textColor = selected ? .white : .secondaryLabelColor
        pin.contentTintColor = selected ? .white : .secondaryLabelColor
    }

    override func layout() {
        super.layout()
        let inner = bounds.insetBy(dx: 10, dy: 0)
        icon.frame = CGRect(x: inner.minX, y: inner.midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize)
        var right = inner.maxX
        for view in [shortcut, pin] as [NSView] where !view.isHidden {
            let size = view.intrinsicContentSize
            view.frame = CGRect(x: right - size.width, y: inner.midY - size.height / 2, width: size.width, height: size.height)
            right -= size.width + Self.spacing
        }
        let left = icon.frame.maxX + Self.spacing
        let height = title.intrinsicContentSize.height
        title.frame = CGRect(x: left, y: inner.midY - height / 2, width: max(0, right - left), height: height)
    }
}

/// Text in an `NSTextView` or the image, with the time, app and size underneath. One view for the panel's
/// life: a step sets a string or an image and changes which one is visible. The text view is TextKit 1 with
/// non-contiguous layout, so only the visible lines are laid out (SwiftUI's `Text` took 650 ms for 4,000
/// characters); TextKit 2's viewport layout cost about a third of each step on top of that.
private final class ClipboardPreviewView: NSView {
    private(set) var itemID: UUID?
    private let textScroll = NSScrollView()
    private let textView = NSTextView(usingTextLayoutManager: false)
    private let imageView = NSImageView()
    private let missingLabel = NSTextField(labelWithString: "Image no longer available")
    private let captionLabel = NSTextField(labelWithString: "")
    private static let padding: CGFloat = 14
    private static let spacing: CGFloat = 8

    init() {
        super.init(frame: .zero)
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textScroll.documentView = textView
        imageView.imageScaling = .scaleProportionallyUpOrDown
        missingLabel.textColor = .secondaryLabelColor
        captionLabel.font = .preferredFont(forTextStyle: .caption1)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byTruncatingTail
        for view in [textScroll, imageView, missingLabel, captionLabel] {
            addSubview(view)
        }
        show(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    func show(_ item: ClipboardItem?) {
        itemID = item?.id
        textScroll.isHidden = item?.kind != .text
        imageView.isHidden = item?.kind != .image
        imageView.image = nil
        missingLabel.isHidden = true
        captionLabel.stringValue = item.map(Self.caption) ?? ""
        if let item, item.kind == .text {
            textView.string = String((item.text ?? "").prefix(20_000))
            textView.scroll(.zero)
        }
    }

    /// No image and not `missing`: the thumbnail is still decoding, so the pane stays blank.
    func showImage(_ image: NSImage?, missing: Bool) {
        if imageView.image !== image {
            imageView.image = image
        }
        missingLabel.isHidden = !missing
    }

    override func layout() {
        super.layout()
        let inner = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let captionHeight = captionLabel.intrinsicContentSize.height
        captionLabel.frame = CGRect(x: inner.minX, y: inner.maxY - captionHeight, width: inner.width, height: captionHeight)
        let content = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: max(0, inner.height - captionHeight - Self.spacing))
        textScroll.frame = content
        imageView.frame = content
        let missing = missingLabel.intrinsicContentSize
        missingLabel.frame = CGRect(x: content.midX - missing.width / 2, y: content.midY - missing.height / 2, width: missing.width, height: missing.height)
    }

    /// Creating a formatter costs milliseconds, and the caption is rebuilt on every arrow key.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    /// App names come from the disk; looked up once each.
    private static var appNames: [String: String] = [:]

    static func caption(for item: ClipboardItem) -> String {
        var parts = [relativeFormatter.localizedString(for: item.date, relativeTo: Date())]
        if let app = item.appBundleID {
            let name = appNames[app] ?? AppNames.displayName(for: app)
            appNames[app] = name
            parts.append(name)
        }
        switch item.kind {
        case .text: parts.append("\((item.text ?? "").count) characters")
        case .image: parts.append("\(item.pixelWidth)×\(item.pixelHeight) · \(ClipboardItem.sizeText(item.byteCount))")
        }
        return parts.joined(separator: " · ")
    }
}

/// App icons by bundle identifier, looked up once each.
@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    private static let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()

    static func icon(for bundleID: String?) -> NSImage {
        guard let bundleID else {
            return fallback
        }
        if let cached = cache[bundleID] {
            return cached
        }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { flattened(NSWorkspace.shared.icon(forFile: $0.path)) } ?? fallback
        cache[bundleID] = image
        return image
    }

    /// App icons carry representations up to 1024 px; drawing one at 24 pt on every redraw is slow.
    /// A 48 px bitmap (sharp on Retina) draws cheaply.
    private static func flattened(_ icon: NSImage) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return icon
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: CGRect(x: 0, y: 0, width: 48, height: 48))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: CGSize(width: 24, height: 24))
        image.addRepresentation(rep)
        return image
    }
}
