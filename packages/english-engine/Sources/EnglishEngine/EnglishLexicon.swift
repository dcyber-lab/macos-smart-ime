import Foundation

public final class EnglishLexicon: Sendable {
    public static let bundled = EnglishLexicon(
        wordsByFrequency: loadBundledLines("wordlist"),
        // supplement.txt is `display<TAB>gloss`; the gloss column feeds EnglishGlossary.
        supplement: loadBundledLines("supplement").map { $0.split(separator: "\t").first.map(String.init) ?? $0 }
    )

    /// Supplement terms rank after the most common words but ahead of the long tail.
    public static let supplementRankOffset = 2000
    /// Words ranked below this (and supplement terms) count as common.
    public static let commonRankLimit = 30_000

    private let sortedKeys: [String]
    private let displays: [String]
    private let ranks: [Int]

    /// `wordsByFrequency` is ordered most frequent first; the position is used as the rank.
    /// `supplement` lists display forms (e.g. "GitHub"); each gets rank `index + supplementRankOffset`
    /// and its display form replaces a word-list entry with the same key.
    public init(wordsByFrequency: [String], supplement: [String] = []) {
        var entries: [String: (display: String, rank: Int)] = [:]
        for (rank, word) in wordsByFrequency.enumerated() {
            let key = Self.key(for: word)
            if !key.isEmpty, entries[key] == nil {
                entries[key] = (word, rank)
            }
        }
        for (index, display) in supplement.enumerated() {
            let key = Self.key(for: display)
            guard !key.isEmpty else {
                continue
            }
            let rank = index + Self.supplementRankOffset
            entries[key] = (display, min(rank, entries[key]?.rank ?? rank))
        }

        let alphabetical = entries.sorted { $0.key < $1.key }
        sortedKeys = alphabetical.map(\.key)
        displays = alphabetical.map(\.value.display)
        ranks = alphabetical.map(\.value.rank)
    }

    public var count: Int {
        sortedKeys.count
    }

    /// Lowercase letters only: "Node.js" -> "nodejs".
    public static func key(for text: String) -> String {
        String(text.lowercased().filter { $0.isASCII && $0.isLetter })
    }

    public func contains(_ word: String) -> Bool {
        index(of: Self.key(for: word)) != nil
    }

    /// True for the most frequent words and supplement terms; false for the long tail.
    public func isCommon(_ word: String) -> Bool {
        index(of: Self.key(for: word)).map { ranks[$0] < Self.commonRankLimit } ?? false
    }

    /// The preferred spelling of `word`, e.g. "github" -> "GitHub".
    public func displayForm(of word: String) -> String? {
        index(of: Self.key(for: word)).map { displays[$0] }
    }

    /// Returns display forms of words whose key starts with `prefix`, most frequent first.
    public func completions(forPrefix prefix: String, limit: Int) -> [String] {
        let key = Self.key(for: prefix)
        guard !key.isEmpty, limit > 0 else {
            return []
        }

        var matches: [(rank: Int, display: String)] = []
        var index = lowerBound(of: key)
        while index < sortedKeys.count, sortedKeys[index].hasPrefix(key) {
            matches.append((ranks[index], displays[index]))
            index += 1
        }

        return matches
            .sorted { $0.rank < $1.rank }
            .prefix(limit)
            .map(\.display)
    }

    private func index(of key: String) -> Int? {
        let index = lowerBound(of: key)
        return index < sortedKeys.count && sortedKeys[index] == key ? index : nil
    }

    private func lowerBound(of value: String) -> Int {
        var low = 0
        var high = sortedKeys.count
        while low < high {
            let mid = (low + high) / 2
            if sortedKeys[mid] < value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func loadBundledLines(_ name: String) -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content.split(whereSeparator: \.isNewline).map(String.init)
    }
}
