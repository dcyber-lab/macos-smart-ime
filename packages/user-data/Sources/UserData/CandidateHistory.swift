import Foundation

/// What the user picks from the candidate list, kept on disk so English candidates follow their habits.
///
/// Two records, both local and bounded:
/// - words: lexicon keys ("github") of English words the user commits;
/// - inputs: for a typed input ("gith", "shujuku"), how often Chinese and each English candidate were picked.
///
/// Lookups are in memory and cheap enough for every keystroke. Changes are written in the background.
public final class CandidateHistory: @unchecked Sendable {
    /// Older use counts half as much after this long.
    public static let halfLife: TimeInterval = 30 * 24 * 60 * 60
    public static let maxWords = 5_000
    public static let maxInputs = 2_000
    static let saveDelay: TimeInterval = 2

    public struct Pick: Equatable, Sendable {
        public let text: String
        public let count: Int
        public let score: Double
    }

    public struct Choices: Equatable, Sendable {
        public static let empty = Choices(chinese: 0, english: [])

        /// Score of all Chinese picks for the input together.
        public let chinese: Double
        /// English picks for the input, highest score first.
        public let english: [Pick]

        public func score(of text: String) -> Double {
            english.first { $0.text == text }?.score ?? 0
        }
    }

    private static let saveQueue = DispatchQueue(label: "lab.dcyber.smartime.candidate-history", qos: .utility)

    private let fileURL: URL?
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var stored: Stored
    private var isSaveScheduled = false

    /// Without a file the history lives in memory only.
    public init(fileURL: URL? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.clock = clock
        stored = fileURL.flatMap(Self.load) ?? Stored()
    }

    // MARK: Words

    /// Records one use of a word, given as its lexicon key.
    public func recordWord(_ key: String) {
        guard !key.isEmpty else {
            return
        }
        let now = self.now
        withLock {
            stored.words[key, default: Usage()].use(at: now)
            trimWords(at: now)
            scheduleSave()
        }
    }

    /// Keys starting with `prefix`, most used first.
    public func words(withPrefix prefix: String, limit: Int) -> [String] {
        guard !prefix.isEmpty, limit > 0 else {
            return []
        }
        let now = self.now
        let matches = withLock {
            stored.words.compactMap { key, usage in
                key.hasPrefix(prefix) ? (key: key, score: usage.score(at: now)) : nil
            }
        }
        return matches
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    // MARK: Choices

    /// Records a pick for `input`: an English candidate's text, or `nil` for any Chinese candidate.
    public func recordChoice(input: String, english text: String?) {
        guard !input.isEmpty else {
            return
        }
        let now = self.now
        withLock {
            var record = stored.inputs[input] ?? InputRecord()
            if let text {
                record.english[text, default: Usage()].use(at: now)
            } else {
                record.chinese.use(at: now)
            }
            stored.inputs[input] = record
            trimInputs(at: now)
            scheduleSave()
        }
    }

    public func choices(for input: String) -> Choices {
        let now = self.now
        guard let record = withLock({ stored.inputs[input] }) else {
            return .empty
        }
        let english = record.english
            .map { Pick(text: $0.key, count: $0.value.count, score: $0.value.score(at: now)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }
        return Choices(chinese: record.chinese.score(at: now), english: english)
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

    /// Runs on `saveQueue`. Encodes a copy so keystrokes never wait for the encoder.
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

    private func trimInputs(at now: TimeInterval) {
        guard stored.inputs.count > Self.maxInputs else {
            return
        }
        let kept = stored.inputs
            .sorted { $0.value.score(at: now) > $1.value.score(at: now) }
            .prefix(Self.maxInputs * 9 / 10)
        stored.inputs = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
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
    var inputs: [String: InputRecord] = [:]
}

private struct InputRecord: Codable {
    var chinese = Usage()
    var english: [String: Usage] = [:]

    func score(at now: TimeInterval) -> Double {
        ([chinese] + english.values).map { $0.score(at: now) }.max() ?? 0
    }
}

/// A decayed use count: each use adds 1, and past uses halve every `CandidateHistory.halfLife`.
private struct Usage: Codable {
    var count = 0
    var weight = 0.0
    /// Seconds since the reference date.
    var lastUsed: TimeInterval = 0

    enum CodingKeys: String, CodingKey {
        case count = "c"
        case weight = "w"
        case lastUsed = "t"
    }

    func score(at now: TimeInterval) -> Double {
        weight * pow(0.5, max(0, now - lastUsed) / CandidateHistory.halfLife)
    }

    mutating func use(at now: TimeInterval) {
        weight = score(at: now) + 1
        count += 1
        lastUsed = now
    }
}
