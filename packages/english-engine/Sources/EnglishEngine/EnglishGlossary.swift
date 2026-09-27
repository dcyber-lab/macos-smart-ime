import Foundation

/// Short Chinese meanings shown next to English candidates.
public final class EnglishGlossary: Sendable {
    public static let bundled = EnglishGlossary(tsv: loadBundledTable())

    private let glosses: [String: String]

    public init(glosses: [String: String]) {
        self.glosses = glosses
    }

    /// Parses `key<TAB>gloss` lines.
    public convenience init(tsv: String) {
        var glosses: [String: String] = [:]
        for line in tsv.utf8.split(separator: UInt8(ascii: "\n")) {
            guard let tab = line.firstIndex(of: UInt8(ascii: "\t")) else {
                continue
            }
            glosses[String(decoding: line[..<tab], as: UTF8.self)] = String(decoding: line[line.index(after: tab)...], as: UTF8.self)
        }
        self.init(glosses: glosses)
    }

    public var count: Int {
        glosses.count
    }

    /// Case-insensitive lookup by the lexicon key ("GitHub" -> "github").
    public func gloss(for word: String) -> String? {
        glosses[EnglishLexicon.key(for: word)]
    }

    private static func loadBundledTable() -> String {
        guard let url = Bundle.module.url(forResource: "en-zh", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }
}
