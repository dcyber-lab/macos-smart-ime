## Context

`IMEInputController.apply(_:sender:)` sees every commit. `sessionStore.reset(committedText:)` already keeps the last commit as `recentText`. The existing learning stores (`CandidateHistory`, `TranslationMisses` in `packages/user-data`) share one pattern: in-memory lookups, decayed counts, bounded sizes, and JSON written in the background on a utility queue. IMK reports the client app through `IMKTextInput.bundleIdentifier()`. Settings live in the input method's defaults domain and are read on use.

## Decisions

### 1. Conclusions always, text in an optional journal

The two derived records are enough for the roadmap, and they are always kept while learning is on:

| Record | Shape | Used by |
|---|---|---|
| App language profile | `bundleID → (hanCharacters, englishWords, lastUsed)`, decayed with a 30-day half-life, at most 500 apps | rewriting (English-dominant apps), per-app candidate order |
| Sentence fingerprints | `HMAC-SHA256(salt, normalized sentence) → (count, lastUsed)`, decayed, at most 5,000 | quick phrases (third repetition) |

The salt is random per install and stored with the memory. Fingerprints keep casual readers out; they are not meant to resist a dictionary attack by someone who already has the user's files, which is stated in the docs. Normalization: trim, collapse whitespace, and lowercase Latin letters. Sentences shorter than 6 characters are not fingerprinted.

The user asked to also keep raw sentences, on by default, to judge whether history is worth its risk. That is the **input journal**:
- **Format**: one JSON line per closed sentence (`{"t": ISO time, "app": bundle ID, "text": sentence}`) appended to `journal/YYYY-MM-DD.jsonl`. Appending never rewrites earlier data, and retention deletes whole day files.
- **Protection**: the directory is 0700, files are 0600, and both are marked `isExcludedFromBackup`.
- **Retention**: `IntelligenceJournalRetentionDays` (default 30) is applied at launch and once a day.
- **Not encrypted.** A Keychain-held key is the right protection, but with ad-hoc signing each update changes the code signature and macOS would ask for Keychain access mid-typing. This is revisited with Developer ID signing or once the trial decides to keep the journal.
- **Same rules as everything else**: the privacy filter and app exclusions run before the journal, so verification codes, URLs, tokens, password managers, and terminals never reach it.

### 2. Sentence assembly lives in the IME, in memory

`SentenceAssembler` keeps one buffer per client app:
- It appends each commit.
- It closes the sentence on 。！？.!?, a newline, `Return`, 10 s without a commit, `deactivateServer`, or a different bundle ID.
- A closed sentence goes through the privacy filter, then to `InputMemory.record(sentence:app:)`.
- The last 5 closed sentences per app stay in memory for later suggestion changes.
- Cost: string appends on commit and one HMAC per sentence. Nothing runs per keystroke.

### 3. Privacy filter before anything is derived

`PrivacyFilter.allows(sentence)` is false when the sentence contains any of:
- 6+ consecutive digits (OTP, phone, card, ID);
- an email address;
- a URL;
- a token-like run of 20+ characters mixing letters and digits.

It is false for the whole sentence; the sentence is not partially masked. `allows(app:)` is false for:
- the default exclusions (`com.1password.1password`, `com.agilebits.onepassword7`, `com.bitwarden.desktop`, `com.apple.keychainaccess`, `com.apple.Passwords`, `com.apple.Terminal`, `com.googlecode.iterm2`, `dev.warp.Warp-Stable`, `com.mitchellh.ghostty`);
- the user's `IntelligenceExcludedApps`;
- an unknown bundle ID.

`IsSecureEventInputEnabled()` also blocks recording.

Default exclusions are a starting point, not a lock. The user tried the first build in Ghostty, where they type to AI tools, and found the menu item checked and disabled. A default-excluded app can now be allowed: it moves into `IntelligenceAllowedApps`, and the sentence rules still apply there.

### 4. Controls in the input menu

The input menu is flat (submenu actions are not delivered; see `add-commit-effects`). It gets a third section after the effect settings:

```
智能中心
  ✓ 智能学习
  ✓ 保存输入原文
    不在「Safari」中学习
    查看学习记录…
    清除学习记录…
```

- **保存输入原文**: toggles the journal; disabled (grayed) while 智能学习 is off. Turning it off stops appending and keeps existing days until they age out or are cleared.

- **Per-app item**: names the current client app (`NSWorkspace` display name) and is checked when the app is not learned. Choosing it toggles a default exclusion in `IntelligenceAllowedApps` and any other app in `IntelligenceExcludedApps`.
- **查看学习记录…**: writes `learning-summary.html` (0600) to the support directory and opens it. It contains:
  - the settings;
  - excluded apps;
  - each app's Chinese/English mix;
  - the fingerprint count and oldest/newest dates;
  - the journal: the last 30 days of sentences, newest first, with app and time, and a search box that filters in the page (no network, no scripts loaded from outside).
- **清除学习记录…**: activates the input method app, shows an `NSAlert` to confirm, then deletes `input-memory.json`, the `journal/` directory, `learning-summary.html`, `candidate-history.json`, and `translation-misses.json`, and resets the in-memory stores.

### 5. 学到了什么: insights computed when the page opens

The user asked what learning has learned. Collecting alone shows nothing, so the learning page opens with insights computed locally from the journal and the memory. They use rules only: `NLTokenizer` for Chinese words and `NSDataDetector` for dates. Each section names the later hub step that will act on it:

| Insight | Rule | Later step |
|---|---|---|
| Overview | sentence and day counts, busiest hours, top apps | — |
| App writing language | Chinese share ≥ 70% Chinese, ≤ 30% English, else mixed (apps with 20+ units) | rewrite suggestions |
| Frequent words | Chinese words of 2+ characters and English words of 3+ letters, stopwords removed, count ≥ 2 | personal terms |
| Possible new words | adjacent single Han characters seen together 3+ times (灵 + 译 → 灵译) | personal terms |
| Repeated sentences | normalized sentences of 6+ characters seen 2+ times | quick phrases |
| Sentences naming a time | the sentence must have a time of day (下午, 三点, 14:30, 3pm); then a detected date, or a "N点" rule; bare dates are ignored | calendar reminders |

- The app names are looked up on the main thread. Tokenizing, detection, rendering, and writing run on a background queue. In an optimized build, a month (3,000 sentences) takes at most 0.2 s.
- Insights are not stored. Nothing in this conversation's tooling reads the user's journal; tests use synthetic sentences.

### 6. Context: the text before the sentence, sessions, launchers

The user found the journal hard to read: each line had only an app and a time ("合了", "我试试", Alfred's "lo"). Three changes need no new permission:

- **Text before the cursor.** When a sentence ends while the client is focused (punctuation or `Return`), the journal entry also stores up to 300 characters before it. They are read through the IMK calls selection translation already uses (`selectedRange`, `attributedSubstring(from:)`). The read happens on the next main-actor turn, after the key has been handled; it is timed per app. An app whose read takes over 100 ms is not read again in that run. Context is stripped of the sentence itself and dropped if it looks sensitive. Sentences closed by a pause, an app switch, or deactivation are not read. The learning page reports reads, hits, and average and slowest time per app. This was planned for the rewrite step; the user moved it here.
- **Sessions.** The page groups the journal into sessions: consecutive sentences in the same app no more than 10 minutes apart, shown oldest first like a conversation.
- **Launchers excluded by default.** Alfred, Raycast, Spotlight, and LaunchBar join the default exclusions; their search terms are not sentences.

Window titles need Accessibility permission and are a separate change. Measured design notes for it are in `docs/intelligence-hub.md`.

### 7. Defaults and storage

- `IntelligenceLearningEnabled` defaults to false. With it off, no file is created and the assembler drops commits.
- `IntelligenceJournalEnabled` defaults to true and only matters while learning is on.
- `input-memory.json` lives in `~/Library/Application Support/SmartIMEHost/`. It is written with POSIX permissions 0600, at most every 2 seconds, on a utility queue.

## Risks

- A sentence split across apps or long pauses is learned as two shorter ones. That is acceptable for language profiles and repetition counts.
- Unknown or missing bundle IDs (some web views) are not learned, which is safer and slightly less useful.
- The HTML summary is a stopgap until the Companion app has a real 智能中心 window.
- The journal is readable by any process running as the user. The user accepted this for the trial; the menu states it.
