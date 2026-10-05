import Foundation
import UserData

/// The page View Learning Data opens: settings, exclusions, per-app language mix, fingerprint counts, and,
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
        /// Window title reads in this run, per app.
        var windowStats: [String: IntelligenceRecorder.ContextStats] = [:]
        var isWindowTitlesEnabled = false
        var isAccessibilityTrusted = false
        var appName: @Sendable (String) -> String
        var generatedAt: Date
    }

    static func html(_ input: Input) -> String {
        let time = DateFormatter()
        time.dateFormat = "yyyy-MM-dd HH:mm"
        func on(_ value: Bool) -> String { value ? "On" : "Off" }

        let apps = input.summary.apps.map { app in
            """
            <tr><td>\(escape(input.appName(app.bundleIdentifier)))</td><td>\(Int(app.hanCharacters.rounded()))</td>\
            <td>\(Int(app.englishWords.rounded()))</td><td>\(Int((app.chineseShare * 100).rounded()))%</td>\
            <td>\(time.string(from: app.lastUsed))</td></tr>
            """
        }.joined(separator: "\n")

        let journal: String
        if !input.isJournalEnabled && input.entries.isEmpty {
            journal = "<p class=\"muted\">Typed text is not saved (menu › Save Typed Text).</p>"
        } else if input.entries.isEmpty {
            journal = "<p class=\"muted\">No records yet.</p>"
        } else {
            let clock = DateFormatter()
            clock.dateFormat = "HH:mm"
            let groups = sessions(input.entries)
            let blocks = groups.map { session -> String in
                let first = session[0], last = session[session.count - 1]
                let lines = session.map { entry -> String in
                    let context = entry.context.map { "<div class=\"ctx\">Context: \(escape($0.count > 80 ? "…" + $0.suffix(80) : $0))</div>" } ?? ""
                    let searchable = (entry.text + " " + (entry.context ?? "")).lowercased()
                    return "<div class=\"line\" data-text=\"\(escape(searchable))\"><span class=\"muted nowrap\">\(clock.string(from: entry.time))</span> \(escape(entry.text))\(context)</div>"
                }.joined()
                let window = first.window.map { " · " + escape($0) } ?? ""
                return """
                <section class="session" data-app="\(escape((input.appName(first.app) + " " + (first.window ?? "")).lowercased()))"><div class="session-head">\(escape(input.appName(first.app)))\(window) · \(time.string(from: first.time))\(first.time == last.time ? "" : "–" + clock.string(from: last.time)) · \(session.count) sentences</div>\(lines)</section>
                """
            }.joined(separator: "\n")
            let summary = "\(input.entries.count) entries in \(groups.count) sessions"
            journal = """
            <input id="q" type="search" placeholder="Search typed text, context, or apps…" autofocus>
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
              count.textContent = term ? `${shown} of \(input.entries.count) match` : '\(summary)';
            });
            </script>
            """
        }

        func costRows(_ stats: [String: IntelligenceRecorder.ContextStats], extra: (String) -> String = { _ in "" }) -> String {
            stats.sorted { $0.value.reads > $1.value.reads }.map { app, stats in
                "<tr><td>\(escape(input.appName(app)))</td><td>\(stats.reads)</td><td>\(stats.found)</td>"
                    + "<td>\(String(format: "%.1f", stats.averageMilliseconds)) ms</td><td>\(String(format: "%.1f", stats.slowestSeconds * 1000)) ms</td>"
                    + "<td>\(stats.isStopped ? "Stopped (one read took over \(Int(IntelligenceRecorder.slowRead * 1000)) ms)" : "OK")</td>\(extra(app))</tr>"
            }.joined()
        }
        let contextRows = costRows(input.contextStats)
        let windowSamples = Dictionary(grouping: input.entries.filter { $0.window != nil }, by: \.app).mapValues { entries in
            var seen: [String] = []
            for title in entries.compactMap(\.window) where !seen.contains(title) && seen.count < 3 { seen.append(title) }
            return seen
        }
        let windowRows = costRows(input.windowStats) { app in
            "<td>\((windowSamples[app] ?? []).map(escape).joined(separator: "<br>"))</td>"
        }
        let windowStatus = !input.isWindowTitlesEnabled ? "Off (menu › Read Window Titles)"
            : input.isAccessibilityTrusted ? "On, Accessibility granted" : "On, but Accessibility is not granted: turn on LinguaType in System Settings › Privacy & Security › Accessibility (you may need to turn it on again after each update)"
        let windowSection = "<p>\(windowStatus)</p>" + (windowRows.isEmpty
            ? "<p class=\"muted\">Nothing read yet in this run.</p>"
            : "<table><tr><th>App</th><th>Reads</th><th>Found</th><th>Average</th><th>Slowest</th><th>Status</th><th>Sample title</th></tr>\(windowRows)</table>")
        let contextSection = contextRows.isEmpty
            ? "<p class=\"muted\">Nothing read yet in this run. After a sentence ends (punctuation or Return), the text before the cursor is read once.</p>"
            : "<table><tr><th>App</th><th>Reads</th><th>Found</th><th>Average</th><th>Slowest</th><th>Status</th></tr>\(contextRows)</table>"

        let learned = insightsSection(input.insights, journalOn: input.isJournalEnabled || !input.entries.isEmpty, appName: input.appName, time: time)
        let fingerprints = input.summary.fingerprintCount == 0 ? "0" : "\(input.summary.fingerprintCount) (\(input.summary.oldestFingerprint.map(time.string(from:)) ?? "") — \(input.summary.newestFingerprint.map(time.string(from:)) ?? ""))"

        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Learning Data</title>
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
        <h1>Learning Data</h1>
        <p class="muted">Generated \(time.string(from: input.generatedAt)). Everything is stored only on this Mac and computed locally with plain rules.</p>
        \(learned)
        <h2>Settings</h2>
        <table>
        <tr><td>Intelligence learning</td><td>\(on(input.isLearningEnabled))</td></tr>
        <tr><td>Save typed text</td><td>\(on(input.isJournalEnabled)); kept for \(input.retentionDays) days, not encrypted</td></tr>
        <tr><td>Apps excluded from learning</td><td>\(escape(input.excludedApps.joined(separator: ", ")))</td></tr>
        </table>
        <h2>Chinese/English mix per app</h2>
        \(input.summary.apps.isEmpty ? "<p class=\"muted\">No records yet.</p>" : "<table><tr><th>App</th><th>Han characters</th><th>English words</th><th>Chinese share</th><th>Last used</th></tr>\n\(apps)\n</table>")
        <h2>Sentence fingerprints</h2>
        <p>\(fingerprints) fingerprints. Only salted hashes and counts are stored, used to spot repeated sentences; they contain no original text.</p>
        <h2>Typed text (last \(input.retentionDays) days)</h2>
        <p class="muted">Sentences in the same app less than 10 minutes apart are grouped into one session. "Context" is the text before the cursor when the sentence ended (only when the app provides it).</p>
        \(journal)
        <h2>Cost of reading context</h2>
        <p class="muted">Reading context means one round trip to the app, done only after a sentence ends and the key has been handled. Stats for this run of the input method:</p>
        \(contextSection)
        <h2>Window titles</h2>
        <p class="muted">Only the title of the current window is read, never its contents. It tells apart conversations, documents, and pages in the same app; chat apps may only show the app name.</p>
        \(windowSection)
        <h2>Never recorded</h2>
        <p class="muted">Password fields and other secure input, apps excluded from learning, and sentences containing 6 or more consecutive digits (codes, card or phone numbers), emails, URLs, or key-like strings.</p>
        </body></html>
        """
    }

    /// "What it learned": the insights, each with the hub step that will act on it.
    private static func insightsSection(_ insights: LearningInsights, journalOn: Bool, appName: (String) -> String, time: DateFormatter) -> String {
        func chips(_ counts: [LearningInsights.Count]) -> String {
            "<div class=\"chips\">" + counts.map { "<span class=\"chip\">\(escape($0.text))<b>\($0.count)</b></span>" }.joined() + "</div>"
        }
        func card(_ title: String, _ body: String, next: String?) -> String {
            "<div class=\"card\"><h3>\(title)</h3>\(body)\(next.map { "<p class=\"next\">\($0)</p>" } ?? "")</div>"
        }
        var cards: [String] = []

        if insights.sentenceCount > 0 {
            let apps = insights.topApps.map { "\(escape(appName($0.text))) \($0.count) sentences" }.joined(separator: ", ")
            let hours = insights.busiestHours.map(\.text).joined(separator: ", ")
            cards.append(card("Overview", "<p>\(insights.sentenceCount) sentences over \(insights.dayCount) days. You type most in \(apps); the most active hours are \(hours).</p>", next: nil))
        }
        if !insights.appLanguages.isEmpty {
            let names: [LearningInsights.Language: String] = [.chinese: "Mostly Chinese", .english: "Mostly English", .mixed: "Mixed"]
            let rows = insights.appLanguages.map {
                "<tr><td>\(escape(appName($0.app)))</td><td>\(names[$0.language] ?? "")</td><td>\(Int(($0.chineseShare * 100).rounded()))%</td></tr>"
            }.joined()
            cards.append(card("Writing language per app", "<table><tr><th>App</th><th>Verdict</th><th>Chinese share</th></tr>\(rows)</table>",
                              next: "Next: after you finish a Chinese sentence in a mostly-English app, it will suggest \"✨ To English\"."))
        }
        guard journalOn else {
            cards.append(card("More insights", "<p class=\"muted\">Frequent words, repeated sentences, and sentences that mention a time need the typed text. Turn on \"Save Typed Text\" in the menu to see them.</p>", next: nil))
            return "<h2>What it learned</h2>" + cards.joined(separator: "\n")
        }
        if insights.sentenceCount == 0 {
            cards.append(card("Still learning", "<p class=\"muted\">No records yet. Type a few more sentences and check back.</p>", next: nil))
            return "<h2>What it learned</h2>" + cards.joined(separator: "\n")
        }
        if !insights.chineseWords.isEmpty || !insights.englishWords.isEmpty {
            cards.append(card("Your frequent words", (insights.chineseWords.isEmpty ? "" : chips(insights.chineseWords))
                + (insights.englishWords.isEmpty ? "" : "<p></p>" + chips(insights.englishWords)),
                next: "Next: these words will rank higher in the candidates."))
        }
        if !insights.newWords.isEmpty {
            cards.append(card("Possible new words", "<p class=\"muted\">Characters you always type one at a time but often appear together.</p>" + chips(insights.newWords),
                              next: "Next: after a few times they become one word, typed in one go."))
        }
        if !insights.repeatedSentences.isEmpty {
            let rows = insights.repeatedSentences.map { "<tr><td>\(escape($0.text))</td><td class=\"nowrap\">\($0.count)×</td></tr>" }.joined()
            cards.append(card("Repeated sentences", "<table>\(rows)</table>", next: "Next: the third time you type the same sentence, it will suggest \"✨ Save as phrase\"."))
        }
        if !insights.schedules.isEmpty {
            let date = DateFormatter()
            date.dateFormat = "MMM d HH:mm"
            let rows = insights.schedules.map {
                "<tr><td>\(escape($0.text))</td><td class=\"nowrap\">\(escape($0.mention))\($0.when.map { " → " + date.string(from: $0) } ?? "")</td></tr>"
            }.joined()
            cards.append(card("Sentences that mention a time", "<table>\(rows)</table>", next: "Next: after you type such a sentence, it will suggest \"✨ Add to calendar\"."))
        }
        return "<h2>What it learned</h2>" + cards.joined(separator: "\n")
    }

    /// Groups entries (newest first) into sessions: consecutive entries in the same app and window no
    /// more than `gap` apart. Sessions come newest first, their entries oldest first, like a conversation.
    static func sessions(_ entries: [InputJournal.Entry], gap: TimeInterval = 600) -> [[InputJournal.Entry]] {
        var result: [[InputJournal.Entry]] = []
        for entry in entries {
            if let previous = result.last?.first, previous.app == entry.app, previous.window == entry.window,
               previous.time.timeIntervalSince(entry.time) <= gap {
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
