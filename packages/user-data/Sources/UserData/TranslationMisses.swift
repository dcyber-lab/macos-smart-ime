import Foundation

/// Chinese words the user commits that have no English translation, so a background task can learn one.
///
/// Holds decayed commit counts per word, the words already translated (kept or not, so each is tried once),
/// and when the task last ran. Local and bounded; changes are written in the background.
public final class TranslationMisses: @unchecked Sendable {
    public static let maxWords = 2_000
    public static let maxProcessed = 5_000
    static let saveDelay: TimeInterval = 2

    public struct Word: Equatable, Sendable {
        public let text: String
        public let count: Int
        public let score: Double
    }

    private static let saveQueue = DispatchQueue(label: "lab.dcyber.smartime.translation-misses", qos: .utility)

    private let fileURL: URL?
    private let clock: @Sendable () -> Date
    private let isEnabled: @Sendable () -> Bool
    private let lock = NSLock()
    private var stored: Stored
    private var isSaveScheduled = false

    /// Without a file the record lives in memory only. Nothing is recorded while `isEnabled` returns false.
    public init(
        fileURL: URL? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        isEnabled: @escaping @Sendable () -> Bool = { true }
    ) {
        self.fileURL = fileURL
        self.clock = clock
        self.isEnabled = isEnabled
        stored = fileURL.flatMap(Self.load) ?? Stored()
    }

    /// Counts one commit of `word`, unless it was translated before.
    public func record(_ word: String) {
        guard !word.isEmpty, isEnabled() else {
            return
        }
        let now = self.now
        withLock {
            guard stored.processed[word] == nil else {
                return
            }
            stored.words[word, default: Usage()].use(at: now)
            trimWords(at: now)
            scheduleSave()
        }
    }

    /// Words with at least `minimumCount` commits, highest score first.
    public func candidates(minimumCount: Int, limit: Int) -> [Word] {
        let now = self.now
        let words = withLock {
            stored.words.compactMap { text, usage in
                usage.count >= minimumCount ? Word(text: text, count: usage.count, score: usage.score(at: now)) : nil
            }
        }
        return Array(
            words
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }
                .prefix(limit)
        )
    }

    public func isProcessed(_ word: String) -> Bool {
        withLock { stored.processed[word] != nil }
    }

    /// Marks `word` as translated, whether or not the translation was kept, and stops counting it.
    public func markProcessed(_ word: String) {
        let now = self.now
        withLock {
            stored.words[word] = nil
            stored.processed[word] = now
            trimProcessed()
            scheduleSave()
        }
    }

    /// Stops counting a word that gained a translation elsewhere; it may be counted again later.
    public func forget(_ word: String) {
        withLock {
            guard stored.words.removeValue(forKey: word) != nil else {
                return
            }
            scheduleSave()
        }
    }

    /// When the learning task last finished.
    public var lastRun: Date? {
        withLock { stored.lastRun.map(Date.init(timeIntervalSinceReferenceDate:)) }
    }

    public func recordRun() {
        let now = self.now
        withLock {
            stored.lastRun = now
            scheduleSave()
        }
    }

    // MARK: Persistence

    /// Writes pending changes now instead of after the batching delay.
    public func flush() {
        Self.saveQueue.sync { write() }
    }

    private func scheduleSave() {
        guard fileURL != nil, !isSaveScheduled else {
            return
        }
        isSaveScheduled = true
        Self.saveQueue.asyncAfter(deadline: .now() + Self.saveDelay) { [self] in
            write()
        }
    }

    /// Runs on `saveQueue`. Encodes a copy so commits never wait for the encoder.
    private func write() {
        guard let fileURL else {
            return
        }
        let snapshot = withLock {
            isSaveScheduled = false
            return stored
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(_ url: URL) -> Stored? {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == Stored.currentVersion else {
            return nil
        }
        return stored
    }

    // MARK: Bounds

    /// Drops the lowest-scoring tenth once the words outgrow their bound.
    private func trimWords(at now: TimeInterval) {
        guard stored.words.count > Self.maxWords else {
            return
        }
        let kept = stored.words
            .sorted { $0.value.score(at: now) > $1.value.score(at: now) }
            .prefix(Self.maxWords * 9 / 10)
        stored.words = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    /// Drops the oldest tenth; a forgotten word may then be counted and translated again.
    private func trimProcessed() {
        guard stored.processed.count > Self.maxProcessed else {
            return
        }
        let kept = stored.processed
            .sorted { $0.value > $1.value }
            .prefix(Self.maxProcessed * 9 / 10)
        stored.processed = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private var now: TimeInterval {
        clock().timeIntervalSinceReferenceDate
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: Stored form

private struct Stored: Codable {
    static let currentVersion = 1

    var version = Stored.currentVersion
    var words: [String: Usage] = [:]
    /// Word -> seconds since the reference date when it was translated.
    var processed: [String: TimeInterval] = [:]
    var lastRun: TimeInterval?
}
