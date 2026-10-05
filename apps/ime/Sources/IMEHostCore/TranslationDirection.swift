import Foundation

enum TranslationDirection: Equatable, Sendable {
    case englishToChinese
    case chineseToEnglish

    var source: Locale.Language {
        self == .englishToChinese ? Locale.Language(identifier: "en") : Locale.Language(identifier: "zh-Hans")
    }

    var target: Locale.Language {
        self == .englishToChinese ? Locale.Language(identifier: "zh-Hans") : Locale.Language(identifier: "en")
    }

    var label: String {
        self == .englishToChinese ? "EN → ZH" : "ZH → EN"
    }

    var languageNames: String {
        self == .englishToChinese ? "English and Simplified Chinese" : "Simplified Chinese and English"
    }

    /// Han characters are weighed against English words (not letters): "这个feature要deploy到production"
    /// (4 vs 3) is Chinese with English terms, "Let's discuss 数据库 design" (3 vs 4) is English.
    static func detect(_ text: String) -> TranslationDirection {
        var hanCharacters = 0
        var englishWords = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let isLatinLetter = scalar.isASCII && CharacterSet.letters.contains(scalar)
            if isLatinLetter, !inWord {
                englishWords += 1
            }
            inWord = isLatinLetter
            if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                hanCharacters += 1
            }
        }
        return hanCharacters > 0 && hanCharacters >= englishWords ? .chineseToEnglish : .englishToChinese
    }
}
