import Foundation

public final class EnglishLexicon: Sendable {
    public static let bundled = EnglishLexicon(wordsByFrequency: loadBundledWords())

    private let sortedWords: [String]
    private let ranks: [Int]

    /// `wordsByFrequency` is ordered most frequent first; the position is used as the rank.
    public init(wordsByFrequency: [String]) {
        var seen = Set<String>()
        let words = wordsByFrequency.filter { !$0.isEmpty && seen.insert($0).inserted }
        let alphabetical = words.enumerated().sorted { $0.element < $1.element }
        sortedWords = alphabetical.map(\.element)
        ranks = alphabetical.map(\.offset)
    }

    public var count: Int {
        sortedWords.count
    }

    /// Returns words starting with `prefix`, most frequent first.
    public func completions(forPrefix prefix: String, limit: Int) -> [String] {
        guard !prefix.isEmpty, limit > 0 else {
            return []
        }

        var matches: [(rank: Int, word: String)] = []
        var index = lowerBound(of: prefix)
        while index < sortedWords.count, sortedWords[index].hasPrefix(prefix) {
            matches.append((ranks[index], sortedWords[index]))
            index += 1
        }

        return matches
            .sorted { $0.rank < $1.rank }
            .prefix(limit)
            .map(\.word)
    }

    private func lowerBound(of value: String) -> Int {
        var low = 0
        var high = sortedWords.count
        while low < high {
            let mid = (low + high) / 2
            if sortedWords[mid] < value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func loadBundledWords() -> [String] {
        guard let url = Bundle.module.url(forResource: "wordlist", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content.split(whereSeparator: \.isNewline).map(String.init)
    }
}
