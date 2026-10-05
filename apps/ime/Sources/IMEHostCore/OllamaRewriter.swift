import Foundation

/// Rewrites with a model served by a local Ollama (`localhost:11434`). Nothing leaves the Mac. Qwen2.5-3B
/// answered in 0.1–0.3 s per sentence on the dev Mac (2.4 s for the first load), with more natural
/// Chinese to English than the on-device model and no guardrail refusals. The text is labelled as
/// data and the answer is cleaned like the on-device free-text answer.
struct OllamaRewriter: AIRewriter {
    static let defaultURL = "http://localhost:11434"
    static let defaultModel = "qwen2.5:3b"

    var baseURL = URL(string: defaultURL)!
    var model = defaultModel
    var timeout: TimeInterval = 15

    func rewrite(_ text: String, action: AIAction) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": "30m",
            "options": ["temperature": 0],
            "messages": [
                ["role": "system", "content": AIPrompt.localInstructions(for: action, answerLabel: AIPrompt.answerLabel(for: action))],
                ["role": "user", "content": "Source: \(text)\n\(AIPrompt.answerLabel(for: action)):"],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AIError.timedOut
        } catch {
            throw AIError.unavailable("Cannot connect to Ollama (\(baseURL.absoluteString))")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIError.failed("Ollama returned an error (run ollama pull \(model) first)")
        }
        guard let content = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
            .flatMap({ $0["message"] as? [String: Any] })?["content"] as? String else {
            throw AIError.emptyResult
        }
        var answer = content.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["Translation:", "Result:"] where answer.hasPrefix(label) {
            answer = String(answer.dropFirst(label.count))
        }
        guard let result = AIPrompt.cleanFreeText(answer, source: text, longForm: action == .organize || action == .explain) else {
            throw AIError.emptyResult
        }
        return result
    }

    /// Whether Ollama answers and has `model`. Called on the main thread when the menu opens, so it
    /// waits at most 0.4 s, and the answer is kept for 30 s.
    static func isAvailable(baseURL: URL, model: String) -> Bool {
        availability.value(for: "\(baseURL.absoluteString)|\(model)") {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"), timeoutInterval: 0.4)
            request.httpMethod = "GET"
            let semaphore = DispatchSemaphore(value: 0)
            var found = false
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data, let names = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["models"] as? [[String: Any]] {
                    found = names.contains { ($0["name"] as? String).map { $0 == model || $0 == model + ":latest" } ?? false }
                }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 0.6)
            return found
        }
    }

    private static let availability = AvailabilityCache()
}

private final class AvailabilityCache: @unchecked Sendable {
    private var entries: [String: (at: Date, value: Bool)] = [:]
    private let lock = NSLock()

    func value(for key: String, compute: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[key], Date().timeIntervalSince(entry.at) < 30 {
            return entry.value
        }
        let value = compute()
        entries[key] = (Date(), value)
        return value
    }
}
