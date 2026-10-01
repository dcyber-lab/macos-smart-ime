import Foundation
import NaturalLanguage
import UserData

/// What the learning page says the input method has learned, computed on the Mac from the journal
/// and the input memory when the page is opened. Rules only, no models. Each section previews a
/// later intelligence hub step (see `docs/intelligence-hub.md`).
struct LearningInsights {
    struct Count: Equatable {
        let text: String
        let count: Int
    }

    struct Schedule: Equatable {
        let text: String
        let app: String
        let when: Date?
        let mention: String
    }

    enum Language: Equatable {
        case chinese
        case english
        case mixed
    }

    struct AppLanguage: Equatable {
        let app: String
        let language: Language
        let chineseShare: Double
    }

    var sentenceCount = 0
    var dayCount = 0
    /// Busiest hours of the day, most sentences first.
    var busiestHours: [Count] = []
    var topApps: [Count] = []
    var chineseWords: [Count] = []
    var englishWords: [Count] = []
    /// Runs of single characters that keep appearing together, e.g. 灵译 typed as 灵 + 译.
    var newWords: [Count] = []
    var repeatedSentences: [Count] = []
    var schedules: [Schedule] = []
    var appLanguages: [AppLanguage] = []

    static let wordLimit = 30
    static let listLimit = 20

    static func compute(entries: [InputJournal.Entry], summary: InputMemory.Summary, calendar: Calendar = .current) -> LearningInsights {
        var insights = LearningInsights()
        insights.appLanguages = summary.apps
            .filter { $0.hanCharacters + $0.englishWords >= 20 }
            .map { AppLanguage(app: $0.bundleIdentifier, language: language(of: $0.chineseShare), chineseShare: $0.chineseShare) }

        guard !entries.isEmpty else {
            return insights
        }
        insights.sentenceCount = entries.count
        insights.dayCount = Set(entries.map { calendar.startOfDay(for: $0.time) }).count
        insights.busiestHours = top(entries.map { String(format: "%02d:00", calendar.component(.hour, from: $0.time)) }, limit: 3)
        insights.topApps = top(entries.map(\.app), limit: 5)

        var chinese: [String: Int] = [:], english: [String: Int] = [:], englishForms: [String: [String: Int]] = [:]
        var pairs: [String: Int] = [:]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        for entry in entries {
            tokenizer.string = entry.text
            let tokens = tokenizer.tokens(for: entry.text.startIndex..<entry.text.endIndex).map { String(entry.text[$0]) }
            for token in tokens {
                if isHan(token), token.count >= 2, !chineseStopwords.contains(token) {
                    chinese[token, default: 0] += 1
                } else if token.count >= 3, token.allSatisfy({ $0.isASCII && $0.isLetter }), !englishStopwords.contains(token.lowercased()) {
                    english[token.lowercased(), default: 0] += 1
                    englishForms[token.lowercased(), default: [:]][token, default: 0] += 1
                }
            }
            for (a, b) in zip(tokens, tokens.dropFirst())
            where a.count == 1 && b.count == 1 && isHan(a) && isHan(b) && !singleStopwords.contains(a) && !singleStopwords.contains(b) {
                pairs[a + b, default: 0] += 1
            }
        }
        insights.chineseWords = top(chinese, minimum: 2, limit: wordLimit)
        insights.englishWords = top(english, minimum: 2, limit: wordLimit).map { word in
            Count(text: englishForms[word.text]?.max { $0.value < $1.value }?.key ?? word.text, count: word.count)
        }
        insights.newWords = top(pairs, minimum: 3, limit: listLimit)

        var sentences: [String: (text: String, count: Int)] = [:]
        for entry in entries where entry.text.count >= SentenceFingerprint.minimumLength {
            let key = SentenceFingerprint.normalize(entry.text)
            sentences[key] = (sentences[key]?.text ?? entry.text, (sentences[key]?.count ?? 0) + 1)
        }
        insights.repeatedSentences = sentences.values
            .filter { $0.count >= 2 }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text }
            .prefix(listLimit)
            .map { Count(text: $0.text, count: $0.count) }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        insights.schedules = Array(entries.lazy.compactMap { schedule($0, detector: detector) }.prefix(listLimit))
        return insights
    }

    // MARK: Rules

    static func language(of chineseShare: Double) -> Language {
        chineseShare >= 0.7 ? .chinese : chineseShare <= 0.3 ? .english : .mixed
    }

    private static let timeWords = ["点", "上午", "下午", "晚上", "早上", "中午", "凌晨", "傍晚"]

    /// 下午, 三点, 14:30, 3pm, tonight… A colon or am/pm only counts next to digits ("team", "npm" do not).
    static func hasTimeOfDay(_ text: String) -> Bool {
        timeWords.contains(where: text.contains)
            || text.range(of: #"(?i)\d\s*[:：]\s*\d|\d\s*(am|pm)\b|\b(noon|tonight|morning|afternoon|evening)\b"#, options: .regularExpression) != nil
    }

    /// A sentence that names a time of day: a detected date whose text has a time marker, or "3点"-style
    /// times the detector misses. Bare dates ("今天天气不错") do not count.
    static func schedule(_ entry: InputJournal.Entry, detector: NSDataDetector?) -> Schedule? {
        let text = entry.text
        // Every accepted mention contains a time marker, so most sentences skip the detector.
        guard hasTimeOfDay(text) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        if let detector {
            for match in detector.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let mention = String(text[swiftRange])
                if hasTimeOfDay(mention) {
                    return Schedule(text: text, app: entry.app, when: match.date, mention: mention)
                }
            }
        }
        if let hit = text.range(of: #"([0-9]{1,2}|[一二三四五六七八九十两]{1,3})点(半|[0-9]{1,2}分)?"#, options: .regularExpression) {
            return Schedule(text: text, app: entry.app, when: nil, mention: String(text[hit]))
        }
        return nil
    }

    private static func isHan(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    private static func top(_ values: [String], limit: Int) -> [Count] {
        top(values.reduce(into: [:]) { $0[$1, default: 0] += 1 }, minimum: 1, limit: limit)
    }

    private static func top(_ counts: [String: Int], minimum: Int, limit: Int) -> [Count] {
        counts
            .filter { $0.value >= minimum }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { Count(text: $0.key, count: $0.value) }
    }

    private static let chineseStopwords: Set<String> = [
        "这个", "那个", "我们", "你们", "他们", "她们", "它们", "什么", "怎么", "为什么", "因为", "所以", "但是", "然后", "还是", "就是",
        "可以", "可能", "应该", "需要", "没有", "不是", "已经", "一下", "一个", "现在", "这样", "那样", "如果", "这些", "那些", "自己",
        "大家", "时候", "知道", "觉得", "比较", "还有", "或者", "以及", "而且", "其实", "这里", "那里", "一些", "有点", "的话",
    ]

    private static let singleStopwords: Set<String> = [
        "的", "了", "是", "我", "你", "他", "她", "它", "在", "和", "与", "把", "被", "给", "也", "都", "就", "还", "又", "很", "吗",
        "呢", "吧", "啊", "呀", "嗯", "哦", "这", "那", "有", "没", "不", "要", "会", "能", "让", "对", "从", "到", "上", "下", "个",
    ]

    private static let englishStopwords: Set<String> = [
        "the", "and", "for", "you", "are", "but", "not", "with", "this", "that", "have", "from", "they", "will", "would", "there",
        "their", "what", "about", "which", "when", "your", "can", "all", "was", "were", "been", "has", "had", "its", "our", "out",
        "into", "than", "then", "them", "these", "those", "just", "also", "some", "any", "please", "could", "should",
    ]
}
