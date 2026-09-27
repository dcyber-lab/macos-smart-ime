import Foundation

public final class ChineseEnglishDictionary: Sendable {
    public static let bundled = ChineseEnglishDictionary(tsv: loadBundledTable())

    private let table: [String: [String]]

    public init(translations: [String: [String]]) {
        table = translations
    }

    /// Parses `chinese<TAB>english[<TAB>english...]` lines.
    public convenience init(tsv: String) {
        var translations: [String: [String]] = [:]
        for line in tsv.utf8.split(separator: UInt8(ascii: "\n")) {
            let fields = line.split(separator: UInt8(ascii: "\t"))
            guard fields.count >= 2 else {
                continue
            }
            translations[String(decoding: fields[0], as: UTF8.self)] = fields.dropFirst().map {
                String(decoding: $0, as: UTF8.self)
            }
        }
        self.init(translations: translations)
    }

    public var count: Int {
        table.count
    }

    public func translations(for chineseWord: String) -> [String] {
        table[chineseWord] ?? []
    }

    private static func loadBundledTable() -> String {
        guard let url = Bundle.module.url(forResource: "zh-en", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }
}
