import Foundation
import UserData

/// The page 查看学习记录 opens: settings, exclusions, per-app language mix, fingerprint counts, and,
/// when the journal is on, recent sentences with a search box. Self-contained: no network, no
/// external scripts, every value HTML-escaped.
enum LearningPage {
    struct Input {
        var isLearningEnabled: Bool
        var isJournalEnabled: Bool
        var retentionDays: Int
        var excludedApps: [String]
        var summary: InputMemory.Summary
        var entries: [InputJournal.Entry]
        var insights: LearningInsights
        /// Reads of the text before the cursor in this run of the input method, per app.
        var contextStats: [String: IntelligenceRecorder.ContextStats] = [:]
        var appName: @Sendable (String) -> String
        var generatedAt: Date
    }

    static func html(_ input: Input) -> String {
        let time = DateFormatter()
        time.dateFormat = "yyyy-MM-dd HH:mm"
        func on(_ value: Bool) -> String { value ? "开" : "关" }

        let apps = input.summary.apps.map { app in
            """
            <tr><td>\(escape(input.appName(app.bundleIdentifier)))</td><td>\(Int(app.hanCharacters.rounded()))</td>\
            <td>\(Int(app.englishWords.rounded()))</td><td>\(Int((app.chineseShare * 100).rounded()))%</td>\
            <td>\(time.string(from: app.lastUsed))</td></tr>
            """
        }.joined(separator: "\n")

        let journal: String
        if !input.isJournalEnabled && input.entries.isEmpty {
            journal = "<p class=\"muted\">未保存输入原文（菜单 › 保存输入原文）。</p>"
        } else if input.entries.isEmpty {
            journal = "<p class=\"muted\">还没有记录。</p>"
        } else {
            let clock = DateFormatter()
            clock.dateFormat = "HH:mm"
            let groups = sessions(input.entries)
            let blocks = groups.map { session -> String in
                let first = session[0], last = session[session.count - 1]
                let lines = session.map { entry -> String in
                    let context = entry.context.map { "<div class=\"ctx\">前文：\(escape($0.count > 80 ? "…" + $0.suffix(80) : $0))</div>" } ?? ""
                    let searchable = (entry.text + " " + (entry.context ?? "")).lowercased()
                    return "<div class=\"line\" data-text=\"\(escape(searchable))\"><span class=\"muted nowrap\">\(clock.string(from: entry.time))</span> \(escape(entry.text))\(context)</div>"
                }.joined()
                return """
                <section class="session" data-app="\(escape(input.appName(first.app).lowercased()))"><div class="session-head">\(escape(input.appName(first.app))) · \(time.string(from: first.time))\(first.time == last.time ? "" : "–" + clock.string(from: last.time)) · \(session.count) 句</div>\(lines)</section>
                """
            }.joined(separator: "\n")
            let summary = "共 \(input.entries.count) 条，\(groups.count) 段"
            journal = """
            <input id="q" type="search" placeholder="搜索输入原文、前文或应用…" autofocus>
            <p class="muted" id="count">\(summary)</p>
            <div id="journal">
            \(blocks)
            </div>
            <script>
            const q = document.getElementById('q'), count = document.getElementById('count');
            const sessions = [...document.querySelectorAll('#journal .session')];
            q.addEventListener('input', () => {
              const term = q.value.trim().toLowerCase();
              let shown = 0;
              for (const session of sessions) {
                const appHit = term && session.dataset.app.includes(term);
                let visible = 0;
                for (const line of session.querySelectorAll('.line')) {
                  const hit = !term || appHit || line.dataset.text.includes(term);
                  line.hidden = !hit; if (hit) { visible++; shown++; }
                }
                session.hidden = visible === 0;
              }
              count.textContent = term ? `匹配 ${shown} / \(input.entries.count) 条` : '\(summary)';
            });
            </script>
            """
        }

        let contextRows = input.contextStats.sorted { $0.value.reads > $1.value.reads }.map { app, stats in
            "<tr><td>\(escape(input.appName(app)))</td><td>\(stats.reads)</td><td>\(stats.found)</td>"
                + "<td>\(String(format: "%.1f", stats.averageMilliseconds)) ms</td><td>\(String(format: "%.1f", stats.slowestSeconds * 1000)) ms</td>"
                + "<td>\(stats.isStopped ? "已停止（有一次超过 \(Int(IntelligenceRecorder.slowRead * 1000)) ms）" : "正常")</td></tr>"
        }.joined()
        let contextSection = contextRows.isEmpty
            ? "<p class=\"muted\">本次运行还没有读取过。句子结束（标点或回车）后，会读一次光标前的文字。</p>"
            : "<table><tr><th>应用</th><th>读取</th><th>读到</th><th>平均</th><th>最长</th><th>状态</th></tr>\(contextRows)</table>"

        let learned = insightsSection(input.insights, journalOn: input.isJournalEnabled || !input.entries.isEmpty, appName: input.appName, time: time)
        let fingerprints = input.summary.fingerprintCount == 0 ? "0 条" : "\(input.summary.fingerprintCount) 条（\(input.summary.oldestFingerprint.map(time.string(from:)) ?? "") — \(input.summary.newestFingerprint.map(time.string(from:)) ?? "")）"

        return """
        <!doctype html>
        <html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>学习记录</title>
        <style>
        :root { --bg: #fff; --fg: #1d1d1f; --muted: #6e6e73; --line: #e5e5ea; --accent: #007aff; }
        @media (prefers-color-scheme: dark) { :root { --bg: #1c1c1e; --fg: #f5f5f7; --muted: #98989d; --line: #38383a; --accent: #0a84ff; } }
        body { background: var(--bg); color: var(--fg); font: 14px/1.5 -apple-system, "PingFang SC", sans-serif; max-width: 960px; margin: 32px auto; padding: 0 16px; }
        h1 { font-size: 24px; } h2 { font-size: 17px; margin-top: 28px; }
        table { border-collapse: collapse; width: 100%; } th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
        th { color: var(--muted); font-weight: 500; } .muted { color: var(--muted); } .nowrap { white-space: nowrap; }
        .chips { display: flex; flex-wrap: wrap; gap: 6px; } .chip { border: 1px solid var(--line); border-radius: 999px; padding: 2px 10px; }
        .chip b { color: var(--muted); font-weight: 500; margin-left: 4px; } .next { color: var(--accent); font-size: 13px; }
        .card { border: 1px solid var(--line); border-radius: 12px; padding: 4px 16px 12px; margin-top: 16px; }
        .session { border-top: 1px solid var(--line); padding: 8px 0; } .session-head { color: var(--muted); font-size: 13px; margin-bottom: 4px; }
        .line { padding: 2px 0; } .ctx { color: var(--muted); font-size: 12px; margin-left: 48px; }
        input[type=search] { width: 100%; padding: 8px 10px; font-size: 15px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); color: var(--fg); box-sizing: border-box; }
        </style></head><body>
        <h1>学习记录</h1>
        <p class="muted">生成于 \(time.string(from: input.generatedAt))。所有内容只保存在这台 Mac 上，在本机按规则统计得出。</p>
        \(learned)
        <h2>设置</h2>
        <table>
        <tr><td>智能学习</td><td>\(on(input.isLearningEnabled))</td></tr>
        <tr><td>保存输入原文</td><td>\(on(input.isJournalEnabled))，保留 \(input.retentionDays) 天，未加密</td></tr>
        <tr><td>不学习的应用</td><td>\(escape(input.excludedApps.joined(separator: "、")))</td></tr>
        </table>
        <h2>各应用的中英文比例</h2>
        \(input.summary.apps.isEmpty ? "<p class=\"muted\">还没有记录。</p>" : "<table><tr><th>应用</th><th>汉字</th><th>英文词</th><th>中文占比</th><th>最近使用</th></tr>\n\(apps)\n</table>")
        <h2>句子指纹</h2>
        <p>\(fingerprints)。只存加盐哈希和次数，用于发现重复输入的句子，不含原文。</p>
        <h2>输入原文（最近 \(input.retentionDays) 天）</h2>
        <p class="muted">同一应用里相隔不超过 10 分钟的句子归为一段。「前文」是句子结束时光标前的文字（应用支持时才有）。</p>
        \(journal)
        <h2>读取前文的开销</h2>
        <p class="muted">读取前文要和对应应用通信一次，只在句子结束、按键处理完之后进行。本次输入法运行期间的统计：</p>
        \(contextSection)
        <h2>从不记录</h2>
        <p class="muted">密码框等安全输入、不学习的应用，以及含 6 位以上连续数字（验证码、卡号、手机号）、邮箱、网址或类似密钥字符串的句子。</p>
        </body></html>
        """
    }

    /// "学到了什么": the insights, each with the hub step that will act on it.
    private static func insightsSection(_ insights: LearningInsights, journalOn: Bool, appName: (String) -> String, time: DateFormatter) -> String {
        func chips(_ counts: [LearningInsights.Count]) -> String {
            "<div class=\"chips\">" + counts.map { "<span class=\"chip\">\(escape($0.text))<b>\($0.count)</b></span>" }.joined() + "</div>"
        }
        func card(_ title: String, _ body: String, next: String?) -> String {
            "<div class=\"card\"><h3>\(title)</h3>\(body)\(next.map { "<p class=\"next\">\($0)</p>" } ?? "")</div>"
        }
        var cards: [String] = []

        if insights.sentenceCount > 0 {
            let apps = insights.topApps.map { "\(escape(appName($0.text))) \($0.count) 句" }.joined(separator: "、")
            let hours = insights.busiestHours.map(\.text).joined(separator: "、")
            cards.append(card("概览", "<p>\(insights.dayCount) 天里记了 \(insights.sentenceCount) 句。最常在 \(apps) 打字；最活跃的时段是 \(hours)。</p>", next: nil))
        }
        if !insights.appLanguages.isEmpty {
            let names: [LearningInsights.Language: String] = [.chinese: "中文为主", .english: "英文为主", .mixed: "中英混写"]
            let rows = insights.appLanguages.map {
                "<tr><td>\(escape(appName($0.app)))</td><td>\(names[$0.language] ?? "")</td><td>\(Int(($0.chineseShare * 100).rounded()))%</td></tr>"
            }.joined()
            cards.append(card("各应用的写作语言", "<table><tr><th>应用</th><th>判断</th><th>中文占比</th></tr>\(rows)</table>",
                              next: "以后：在英文为主的应用里打完一句中文，会提示「✨ 转成英文」。"))
        }
        guard journalOn else {
            cards.append(card("更多洞察", "<p class=\"muted\">常用词、重复的话和提到时间的句子需要输入原文。打开菜单里的「保存输入原文」后可见。</p>", next: nil))
            return "<h2>学到了什么</h2>" + cards.joined(separator: "\n")
        }
        if insights.sentenceCount == 0 {
            cards.append(card("还在学习", "<p class=\"muted\">还没有记录。多打几句后再来看。</p>", next: nil))
            return "<h2>学到了什么</h2>" + cards.joined(separator: "\n")
        }
        if !insights.chineseWords.isEmpty || !insights.englishWords.isEmpty {
            cards.append(card("你的常用词", (insights.chineseWords.isEmpty ? "" : chips(insights.chineseWords))
                + (insights.englishWords.isEmpty ? "" : "<p></p>" + chips(insights.englishWords)),
                next: "以后：这些词会更靠前出现在候选里。"))
        }
        if !insights.newWords.isEmpty {
            cards.append(card("可能的新词", "<p class=\"muted\">总是一个字一个字打出来、但经常连在一起的字。</p>" + chips(insights.newWords),
                              next: "以后：几次之后自动变成整词，一次打出。"))
        }
        if !insights.repeatedSentences.isEmpty {
            let rows = insights.repeatedSentences.map { "<tr><td>\(escape($0.text))</td><td class=\"nowrap\">\($0.count) 次</td></tr>" }.joined()
            cards.append(card("重复说过的话", "<table>\(rows)</table>", next: "以后：第三次打同一句话时，会提示「✨ 存成短语」。"))
        }
        if !insights.schedules.isEmpty {
            let date = DateFormatter()
            date.dateFormat = "M月d日 HH:mm"
            let rows = insights.schedules.map {
                "<tr><td>\(escape($0.text))</td><td class=\"nowrap\">\(escape($0.mention))\($0.when.map { " → " + date.string(from: $0) } ?? "")</td></tr>"
            }.joined()
            cards.append(card("提到时间的句子", "<table>\(rows)</table>", next: "以后：打完这样的句子，会提示「✨ 加到日历」。"))
        }
        return "<h2>学到了什么</h2>" + cards.joined(separator: "\n")
    }

    /// Groups entries (newest first) into sessions: consecutive entries in the same app no more than
    /// `gap` apart. Sessions come newest first, their entries oldest first, like a conversation.
    static func sessions(_ entries: [InputJournal.Entry], gap: TimeInterval = 600) -> [[InputJournal.Entry]] {
        var result: [[InputJournal.Entry]] = []
        for entry in entries {
            if let previous = result.last?.first, previous.app == entry.app, previous.time.timeIntervalSince(entry.time) <= gap {
                result[result.count - 1].insert(entry, at: 0)
            } else {
                result.append([entry])
            }
        }
        return result
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
