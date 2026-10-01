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

- **Per-app item**: names the current client app (`NSWorkspace` display name) and toggles it in `IntelligenceExcludedApps`.
- **查看学习记录…**: writes `learning-summary.html` (0600) to the support directory and opens it. It contains:
  - the settings;
  - excluded apps;
  - each app's Chinese/English mix;
  - the fingerprint count and oldest/newest dates;
  - the journal: the last 30 days of sentences, newest first, with app and time, and a search box that filters in the page (no network, no scripts loaded from outside).
- **清除学习记录…**: activates the input method app, shows an `NSAlert` to confirm, then deletes `input-memory.json`, the `journal/` directory, `learning-summary.html`, `candidate-history.json`, and `translation-misses.json`, and resets the in-memory stores.

### 5. Defaults and storage

- `IntelligenceLearningEnabled` defaults to false. With it off, no file is created and the assembler drops commits.
- `IntelligenceJournalEnabled` defaults to true and only matters while learning is on.
- `input-memory.json` lives in `~/Library/Application Support/SmartIMEHost/`. It is written with POSIX permissions 0600, at most every 2 seconds, on a utility queue.

## Risks

- A sentence split across apps or long pauses is learned as two shorter ones. That is acceptable for language profiles and repetition counts.
- Unknown or missing bundle IDs (some web views) are not learned, which is safer and slightly less useful.
- The HTML summary is a stopgap until the Companion app has a real 智能中心 window.
- The journal is readable by any process running as the user. The user accepted this for the trial; the menu states it.
