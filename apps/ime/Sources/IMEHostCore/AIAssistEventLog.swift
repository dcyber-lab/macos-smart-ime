import Foundation
import UserData

/// A small local log of AI chip events (time, app, event; never text), so a try that did not work can
/// be explained without anyone reading what was typed. Keeps the last 500 lines.
final class AIAssistEventLog: @unchecked Sendable {
    static let shared = AIAssistEventLog(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SmartIMEHost/ai-assist-events.log"))
    static let maxLines = 500

    private let url: URL
    private let queue = DispatchQueue(label: "lab.dcyber.smartime.ai-assist-log", qos: .utility)
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(url: URL) {
        self.url = url
    }

    func append(_ event: String, app: String) {
        let line = "\(formatter.string(from: Date()))\t\(app)\t\(event)\n"
        queue.async { [url] in
            var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            lines.append(String(line.dropLast()))
            let kept = lines.suffix(Self.maxLines).joined(separator: "\n") + "\n"
            PrivateFiles.write(Data(kept.utf8), to: url)
        }
    }

    func flush() {
        queue.sync {}
    }
}
