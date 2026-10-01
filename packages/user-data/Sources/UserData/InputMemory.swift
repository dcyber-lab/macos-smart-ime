import Foundation

/// What the intelligence hub keeps about committed sentences, without their text:
/// - per app, how much Chinese and English the user writes there;
/// - salted fingerprints of sentences with how often each was typed.
///
/// Local and bounded, decayed like `CandidateHistory`, written in the background with mode 0600.
public final class InputMemory: @unchecked Sendable {
    public static let maxApps = 500
    public static let maxFingerprints = 5_000
    static let saveDelay: TimeInterval = 2

    public struct AppProfile: Equatable, Sendable {
        public let bundleIdentifier: String
        /// Decayed counts.
        public let hanCharacters: Double
        public let englishWords: Double
        public let lastUsed: Date

        /// Share of Chinese in what the user writes in this app, 0...1.
        public var chineseShare: Double {
            let total = hanCharacters + englishWords
            return total > 0 ? hanCharacters / total : 0
        }
    }

    public struct Summary: Equatable, Sendable {
        public let apps: [AppProfile]
        public let fingerprintCount: Int
        public let oldestFingerprint: Date?
        public let newestFingerprint: Date?
    }

    private static let saveQueue = DispatchQueue(label: "lab.dcyber.smartime.input-memory", qos: .utility)

    private let fileURL: URL?
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var stored: Stored
    private var isSaveScheduled = false

    /// Without a file the memory lives in memory only.
    public init(fileURL: URL? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.clock = clock
        stored = fileURL.flatMap(Self.load) ?? Stored()
    }

    /// Records one sentence the privacy filter allowed. Returns how often it has now been typed
    /// (decayed count of its fingerprint), or nil when it is too short to fingerprint.
    @discardableResult
    public func record(sentence: String, app bundleIdentifier: String) -> Int? {
        let (han, english) = Self.languageCounts(sentence)
        let now = self.now
        let count: Int? = withLock {
            var profile = stored.apps[bundleIdentifier] ?? StoredProfile()
            profile.add(han: Double(han), english: Double(english), at: now)
            stored.apps[bundleIdentifier] = profile
            trimApps(at: now)

            guard let fingerprint = SentenceFingerprint.make(sentence, salt: stored.saltData) else {
                return nil
            }
            stored.fingerprints[fingerprint, default: Usage()].use(at: now)
            let count = stored.fingerprints[fingerprint]?.count
            trimFingerprints(at: now)
            return count
        }
        scheduleSave()
        return count
    }

    public func profile(for bundleIdentifier: String) -> AppProfile? {
        let now = self.now
        return withLock { stored.apps[bundleIdentifier].map { $0.profile(bundleIdentifier, at: now) } }
    }

    /// How often this sentence was recorded; 0 when never or too short.
    public func timesTyped(_ sentence: String) -> Int {
        withLock {
            SentenceFingerprint.make(sentence, salt: stored.saltData).flatMap { stored.fingerprints[$0]?.count } ?? 0
        }
    }

    public func summary() -> Summary {
        let now = self.now
        return withLock {
            let apps = stored.apps
                .map { $0.value.profile($0.key, at: now) }
                .sorted { $0.hanCharacters + $0.englishWords > $1.hanCharacters + $1.englishWords }
            let dates = stored.fingerprints.values.map { Date(timeIntervalSinceReferenceDate: $0.lastUsed) }
            return Summary(apps: apps, fingerprintCount: stored.fingerprints.count, oldestFingerprint: dates.min(), newestFingerprint: dates.max())
        }
    }

    /// Forgets everything, including the salt, and deletes the file.
    public func clear() {
        withLock { stored = Stored() }
        guard let fileURL else {
            return
        }
        Self.saveQueue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Han characters, and runs of Latin letters as English words.
    static func languageCounts(_ text: String) -> (han: Int, english: Int) {
        var han = 0, english = 0, inWord = false
        for scalar in text.unicodeScalars {
            let isLatin = scalar.isASCII && CharacterSet.letters.contains(scalar)
            if isLatin, !inWord {
                english += 1
            }
            inWord = isLatin
            if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                han += 1
            }
        }
        return (han, english)
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

    /// Runs on `saveQueue`.
    private func write() {
        guard let fileURL else {
            return
        }
        let snapshot = withLock {
            isSaveScheduled = false
            return stored
        }
        guard !snapshot.apps.isEmpty || !snapshot.fingerprints.isEmpty,
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        PrivateFiles.write(data, to: fileURL)
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

    private func trimApps(at now: TimeInterval) {
        guard stored.apps.count > Self.maxApps else {
            return
        }
        let kept = stored.apps.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(Self.maxApps * 9 / 10)
        stored.apps = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private func trimFingerprints(at now: TimeInterval) {
        guard stored.fingerprints.count > Self.maxFingerprints else {
            return
        }
        let kept = stored.fingerprints
            .sorted { $0.value.score(at: now) > $1.value.score(at: now) }
            .prefix(Self.maxFingerprints * 9 / 10)
        stored.fingerprints = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
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

private struct StoredProfile: Codable {
    var han = 0.0
    var english = 0.0
    var lastUsed: TimeInterval = 0

    enum CodingKeys: String, CodingKey {
        case han = "h"
        case english = "e"
        case lastUsed = "t"
    }

    mutating func add(han: Double, english: Double, at now: TimeInterval) {
        let decay = pow(0.5, max(0, now - lastUsed) / CandidateHistory.halfLife)
        self.han = self.han * decay + han
        self.english = self.english * decay + english
        lastUsed = now
    }

    func profile(_ bundleIdentifier: String, at now: TimeInterval) -> InputMemory.AppProfile {
        let decay = pow(0.5, max(0, now - lastUsed) / CandidateHistory.halfLife)
        return InputMemory.AppProfile(
            bundleIdentifier: bundleIdentifier, hanCharacters: han * decay, englishWords: english * decay,
            lastUsed: Date(timeIntervalSinceReferenceDate: lastUsed)
        )
    }
}

private struct Stored: Codable {
    static let currentVersion = 1

    var version = Stored.currentVersion
    /// Random per install (and per clear), base64.
    var salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
    var apps: [String: StoredProfile] = [:]
    var fingerprints: [String: Usage] = [:]

    var saltData: Data {
        Data(base64Encoded: salt) ?? Data(salt.utf8)
    }
}
