import CryptoKit
import Foundation
import UserData

/// One thing copied: text, or an image kept as a PNG file next to the index.
struct ClipboardItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case text, image
    }

    let id: UUID
    let kind: Kind
    var text: String?
    var imageFile: String?
    var pixelWidth = 0
    var pixelHeight = 0
    var byteCount = 0
    var date: Date
    var appBundleID: String?
    /// Same content, same digest: copying something again moves the entry up instead of adding one.
    let digest: String

    /// One line for the list: the first non-empty line of text, or "Image: 975x541 (2.0 MB)".
    var title: String {
        switch kind {
        case .text:
            let line = (text ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return line ?? "(blank)"
        case .image:
            return "Image: \(pixelWidth)×\(pixelHeight) (\(Self.sizeText(byteCount)))"
        }
    }

    static func sizeText(_ bytes: Int) -> String {
        bytes >= 1_000_000 ? String(format: "%.1f MB", Double(bytes) / 1_000_000) : "\(max(1, bytes / 1000)) KB"
    }
}

/// The clipboard history on disk: `index.json` plus `images/<id>.png`, readable only by the user. Newest
/// first, capped by count and age; pinned entries are kept past both.
@MainActor
final class ClipboardHistoryStore {
    static let maxTextBytes = 1_000_000
    static let maxImageBytes = 20_000_000

    private(set) var items: [ClipboardItem] = []
    private(set) var pinned: Set<UUID> = []
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }
    var maxItems: Int
    var retentionDays: Int

    private struct Index: Codable {
        var items: [ClipboardItem]
        var pinned: [UUID]
    }

    init(directory: URL, maxItems: Int = 300, retentionDays: Int = 30) {
        self.directory = directory
        self.maxItems = maxItems
        self.retentionDays = retentionDays
        load()
    }

    // MARK: Adding

    /// Returns false for empty or oversized text.
    @discardableResult
    func addText(_ text: String, app: String?, now: Date = Date()) -> Bool {
        let bytes = text.utf8.count
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, bytes <= Self.maxTextBytes else {
            return false
        }
        let digest = Self.digest(Data(text.utf8), prefix: "t")
        if bump(digest, app: app, now: now) {
            return true
        }
        insert(ClipboardItem(id: UUID(), kind: .text, text: text, byteCount: bytes, date: now, appBundleID: app, digest: digest))
        return true
    }

    @discardableResult
    func addImage(png: Data, width: Int, height: Int, app: String?, now: Date = Date()) -> Bool {
        guard !png.isEmpty, png.count <= Self.maxImageBytes else {
            return false
        }
        let digest = Self.digest(png, prefix: "i")
        if bump(digest, app: app, now: now) {
            return true
        }
        let id = UUID()
        let file = "\(id.uuidString).png"
        PrivateFiles.prepareDirectory(imagesURL)
        PrivateFiles.write(png, to: imagesURL.appendingPathComponent(file))
        insert(ClipboardItem(
            id: id, kind: .image, imageFile: file, pixelWidth: width, pixelHeight: height,
            byteCount: png.count, date: now, appBundleID: app, digest: digest
        ))
        return true
    }

    // MARK: Reading

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesURL.appendingPathComponent($0) }
    }

    func isPinned(_ item: ClipboardItem) -> Bool {
        pinned.contains(item.id)
    }

    /// Pinned entries first, then newest first; `query` keeps entries whose text contains every word.
    func search(_ query: String) -> [ClipboardItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = items.filter { item in
            words.allSatisfy { word in
                switch item.kind {
                case .text: return item.text?.localizedCaseInsensitiveContains(word) == true
                case .image: return "image".localizedCaseInsensitiveContains(word)
                }
            }
        }
        return matches.filter { pinned.contains($0.id) } + matches.filter { !pinned.contains($0.id) }
    }

    // MARK: Changing

    func togglePin(_ item: ClipboardItem) {
        if !pinned.insert(item.id).inserted {
            pinned.remove(item.id)
        }
        save()
    }

    func remove(_ item: ClipboardItem) {
        drop([item])
        save()
    }

    /// Removes everything except pinned entries.
    func clear(keepPinned: Bool = true) {
        drop(items.filter { !keepPinned || !pinned.contains($0.id) })
        save()
    }

    /// Drops what is older than the retention period or beyond the count cap, pinned entries aside.
    func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        var kept = 0
        var doomed: [ClipboardItem] = []
        for item in items where !pinned.contains(item.id) {
            kept += 1
            if item.date < cutoff || kept > maxItems {
                doomed.append(item)
            }
        }
        if !doomed.isEmpty {
            drop(doomed)
            save()
        }
    }

    // MARK: Storage

    private func bump(_ digest: String, app: String?, now: Date) -> Bool {
        guard let index = items.firstIndex(where: { $0.digest == digest }) else {
            return false
        }
        var item = items.remove(at: index)
        item.date = now
        item.appBundleID = app ?? item.appBundleID
        items.insert(item, at: 0)
        save()
        return true
    }

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        prune(now: item.date)
        save()
    }

    private func drop(_ doomed: [ClipboardItem]) {
        let ids = Set(doomed.map(\.id))
        for item in doomed {
            if let url = imageURL(for: item) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        items.removeAll { ids.contains($0.id) }
        pinned.subtract(ids)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data) else {
            return
        }
        let known = Set(index.items.map(\.id))
        items = index.items
        pinned = Set(index.pinned).intersection(known)
    }

    private func save() {
        PrivateFiles.prepareDirectory(directory)
        let index = Index(items: items, pinned: Array(pinned))
        if let data = try? JSONEncoder().encode(index) {
            PrivateFiles.write(data, to: indexURL)
        }
    }

    private static func digest(_ data: Data, prefix: String) -> String {
        prefix + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
