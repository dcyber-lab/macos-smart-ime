import Foundation

/// The optional input journal: committed sentences with app and time, one JSON line each, in a
/// file per day. The directory is 0700, files are 0600, both excluded from backups, and days
/// older than the retention period are deleted. Not encrypted.
public final class InputJournal: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let time: Date
        public let app: String
        public let text: String

        public init(time: Date, app: String, text: String) {
            self.time = time
            self.app = app
            self.text = text
        }

        enum CodingKeys: String, CodingKey {
            case time = "t"
            case app
            case text
        }
    }

    private let directoryURL: URL
    private let clock: @Sendable () -> Date
    private let queue = DispatchQueue(label: "lab.dcyber.smartime.input-journal", qos: .utility)
    private let calendar: Calendar

    public init(directoryURL: URL, clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.directoryURL = directoryURL
        self.clock = clock
        self.calendar = calendar
    }

    /// Appends in the background; never blocks the caller on disk.
    public func append(_ text: String, app: String) {
        let entry = Entry(time: clock(), app: app, text: text)
        queue.async { [self] in
            write(entry)
        }
    }

    /// Entries from the last `days` days, newest first.
    public func entries(days: Int, limit: Int = 5_000) -> [Entry] {
        queue.sync {
            dayFiles()
                .filter { $0.day >= startOfDay(daysAgo: days - 1) }
                .sorted { $0.day > $1.day }
                .lazy
                .flatMap { Self.read($0.url).reversed() }
                .prefix(limit)
                .map { $0 }
        }
    }

    /// Deletes day files older than `days` days (today counts as the first).
    public func prune(keepingDays days: Int) {
        queue.async { [self] in
            let oldest = startOfDay(daysAgo: max(1, days) - 1)
            for file in dayFiles() where file.day < oldest {
                try? FileManager.default.removeItem(at: file.url)
            }
        }
    }

    public func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    /// Waits for pending appends.
    public func flush() {
        queue.sync {}
    }

    // MARK: Files

    private func write(_ entry: Entry) {
        PrivateFiles.prepareDirectory(directoryURL)
        let url = directoryURL.appendingPathComponent(Self.fileName(for: entry.time, calendar: calendar))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else {
            return
        }
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            PrivateFiles.restrict(url)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private func dayFiles() -> [(day: Date, url: URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".jsonl"), let day = Self.dayFormatter(calendar).date(from: String(name.dropLast(6))) else {
                return nil
            }
            return (day, directoryURL.appendingPathComponent(name))
        }
    }

    private func startOfDay(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: clock())) ?? .distantPast
    }

    static func fileName(for date: Date, calendar: Calendar) -> String {
        dayFormatter(calendar).string(from: date) + ".jsonl"
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func read(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Entry.self, from: Data($0)) }
    }
}
