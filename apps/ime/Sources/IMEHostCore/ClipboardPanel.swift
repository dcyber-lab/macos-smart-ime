import AppKit
import ImageIO
import SwiftUI

/// What the clipboard panel shows: a search field, the matches, and a preview of the chosen one.
@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published var query = "" {
        didSet { reload() }
    }
    @Published private(set) var results: [ClipboardItem] = []
    @Published var selection = 0

    let store: ClipboardHistoryStore
    var onChoose: (ClipboardItem) -> Void = { _ in }

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    var selected: ClipboardItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    private let previews = NSCache<NSUUID, NSImage>()

    /// A screen-sized copy of the image, decoded once per entry: decoding the full file on every
    /// selection change made ↑↓ stutter.
    func previewImage(for item: ClipboardItem) -> NSImage? {
        if let cached = previews.object(forKey: item.id as NSUUID) {
            return cached
        }
        guard let url = store.imageURL(for: item),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1200,
              ] as CFDictionary)
        else {
            return nil
        }
        let image = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        previews.setObject(image, forKey: item.id as NSUUID)
        return image
    }

    func reload() {
        results = store.search(query)
        selection = min(selection, max(0, results.count - 1))
    }

    func reset() {
        query = ""
        selection = 0
        reload()
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else {
            return
        }
        selection = min(max(selection + delta, 0), results.count - 1)
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
/// deletes, Esc closes. It takes the keyboard without activating the app, so the app in front stays in front.
@MainActor
final class ClipboardPanel: NSPanel {
    static let size = CGSize(width: 760, height: 440)

    private let model: ClipboardPanelModel
    private var monitor: Any?

    init(store: ClipboardHistoryStore, onChoose: @escaping (ClipboardItem) -> Void) {
        model = ClipboardPanelModel(store: store)
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
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: Self.size))
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.maskImage = CandidatePanel.roundedMask(radius: 14)
        let host = NSHostingView(rootView: ClipboardPanelView(model: model))
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    func show() {
        model.reset()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: Self.size)
        setFrameOrigin(CGPoint(x: visible.midX - Self.size.width / 2, y: visible.midY - Self.size.height / 2 + visible.height * 0.12))
        makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    override func close() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        super.close()
    }

    /// A click in another app takes the keyboard away.
    override func resignKey() {
        super.resignKey()
        if isVisible {
            close()
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === self else {
            return false
        }
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
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

// MARK: - Views

private struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索剪贴板历史", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($searchFocused)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            Divider()
            if model.results.isEmpty {
                Spacer()
                Text(model.query.isEmpty ? "还没有复制过任何内容" : "没有匹配的内容")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack(spacing: 0) {
                    list.frame(width: 360)
                    Divider()
                    ClipboardPreview(model: model)
                }
            }
            Divider()
            Text("↑↓ 选择 · ⏎ 粘贴 · ⌘1–9 直接粘贴 · ⌘P 置顶 · ⌘⌫ 删除 · Esc 关闭")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 7)
        }
        .onAppear { searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        ClipboardRow(item: item, index: index, isSelected: index == model.selection, isPinned: model.store.isPinned(item))
                            .equatable()
                            .id(item.id)
                            .onTapGesture { model.selection = index }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.choose(at: index) })
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selection) { _ in
                if let item = model.selected {
                    proxy.scrollTo(item.id)
                }
            }
        }
    }
}

private struct ClipboardRow: View, Equatable {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.icon(for: item.appBundleID))
                .resizable()
                .frame(width: 24, height: 24)
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isPinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
            }
            if index < 9 {
                Text("⌘\(index + 1)").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
    }
}

private struct ClipboardPreview: View {
    @ObservedObject var model: ClipboardPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = model.selected {
                switch item.kind {
                case .text:
                    ScrollView {
                        Text(String((item.text ?? "").prefix(4_000)))
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .image:
                    if let image = model.previewImage(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("图片已不在").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Text(Self.caption(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Creating a formatter costs milliseconds, and the caption is rebuilt on every arrow key.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    static func caption(for item: ClipboardItem) -> String {
        var parts = [relativeFormatter.localizedString(for: item.date, relativeTo: Date())]
        if let app = item.appBundleID {
            parts.append(AppNames.displayName(for: app))
        }
        switch item.kind {
        case .text: parts.append("\((item.text ?? "").count) 个字符")
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
