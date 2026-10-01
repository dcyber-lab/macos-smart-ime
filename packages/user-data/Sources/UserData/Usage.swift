import Foundation

/// A decayed use count: each use adds 1, and past uses halve every `CandidateHistory.halfLife`.
struct Usage: Codable {
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
