import Foundation

/// The user's own Chinese-to-English translations (`user-translations.tsv`), looked up before the built-in table:
/// lines the user writes, and translations learned from words they commit often.
///
/// Same format as the built-in supplement: `chinese<TAB>english[<TAB>english]`, `#` starts a comment line.
public final class UserTranslations: @unchecked Sendable {
    static let maxTranslations = 2
    static let header = """
        # Your Chinese-to-English translations, one per line: chinese<TAB>english[<TAB>english].
        # They take precedence over the built-in table. Edits apply after switching to another app and back.
        """
    static let learnedHeader = "# Learned automatically from words you type often. Delete a line to drop it for good."

    private let fileURL: URL?
    private let lock = NSLock()
    private var table: [String: [String]] = [:]
    private var loadedModificationDate: Date?

    /// Without a file the translations live in memory only.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        reloadIfChanged()
    }

    /// Nil when the user has no translation for the word.
    public func translations(for word: String) -> [String]? {
        withLock { table[word] }
    }

    public var count: Int {
        withLock { table.count }
    }

    /// Rereads the file when it changed since it was last read; cheap enough to call on every activation.
    public func reloadIfChanged() {
        guard let fileURL else {
            return
        }
        let modificationDate = Self.modificationDate(of: fileURL)
        guard withLock({ modificationDate != loadedModificationDate }) else {
            return
        }
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let parsed = Self.parse(content)
        withLock {
            table = parsed
            loadedModificationDate = modificationDate
        }
    }

    /// Appends a learned translation to the file, under the learned section, and applies it immediately.
    public func addLearned(_ word: String, translations: [String]) {
        let translations = Array(translations.prefix(Self.maxTranslations))
        guard !word.isEmpty, !translations.isEmpty else {
            return
        }
        withLock { table[word] = translations }
        guard let fileURL else {
            return
        }
        var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? Self.header + "\n"
        if !content.isEmpty, !content.hasSuffix("\n") {
            content += "\n"
        }
        if !content.split(separator: "\n").contains(Substring(Self.learnedHeader)) {
            content += "\n" + Self.learnedHeader + "\n"
        }
        content += ([word] + translations).joined(separator: "\t") + "\n"
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        let modificationDate = Self.modificationDate(of: fileURL)
        withLock { loadedModificationDate = modificationDate }
    }

    static func parse(_ content: String) -> [String: [String]] {
        var table: [String: [String]] = [:]
        for line in content.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            let translations = fields.dropFirst().filter { !$0.isEmpty }.prefix(maxTranslations)
            guard let word = fields.first, !word.isEmpty, !translations.isEmpty else {
                continue
            }
            table[word] = Array(translations)
        }
        return table
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
