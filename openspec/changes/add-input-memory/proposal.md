## Why

The user wants the input method to become an AI entry point: learn from what they type and offer help. They decided (2026-10-01) that learned data stays on the Mac and that help is offered, never applied automatically. Every later feature (better candidates, rewriting, reminders, quick phrases; see `docs/intelligence-hub.md`) needs the same foundation: a privacy-safe record of committed text, per app, with controls the user can see. This change builds that foundation and no suggestions yet.

## What Changes

- **Sentence assembly**: committed text is joined per client app into sentences. A sentence ends at sentence punctuation, `Return`, a 10 s pause, or a focus or app change. The last few sentences are kept in memory only, for later suggestion features.
- **Input memory** (`packages/user-data`, `input-memory.json`): stores derived data:
  - Per-app language profile: decayed counts of committed Han characters and English words.
  - Sentence fingerprints: salted SHA-256 of normalized sentences of 6+ characters, with decayed counts and no text.
- **Input journal** (保存输入原文), added at the user's request as a trial:
  - Keeps closed sentences with app and time in `journal/YYYY-MM-DD.jsonl`.
  - On by default while learning is on; it has its own menu toggle.
  - Retention is 30 days, the file mode is 0600, and it is excluded from Time Machine.
  - It is not encrypted. Sensitive sentences and excluded apps are filtered before it, as for everything else.
- **Privacy rules**, applied before anything is derived:
  - Learning is off until the user enables it.
  - Excluded apps record nothing. Defaults are password managers and terminals; the user can add apps.
  - Secure input records nothing.
  - A sentence with 6+ consecutive digits, an email address, a URL, or a token-like string is dropped whole.
  - The store is bounded, has file mode 0600, and the input method makes no network calls.
- **Input menu, new section 智能中心**:
  - 智能学习 (on/off).
  - 保存输入原文 (on/off; on by default).
  - 不在「<App>」中学习 (toggles the current app).
  - 查看学习记录… writes a local page and opens it: a summary plus a searchable list of journal sentences.
  - 清除学习记录… asks for confirmation, then deletes this store, the journal, `candidate-history.json`, and `translation-misses.json`.
- **Docs**: the project brief and technical design gain the intelligence hub's principles; `docs/intelligence-hub.md` holds the roadmap.

## Non-goals

- Any suggestion UI or action (changes 2–5 in the roadmap).
- Encrypting the journal (deferred; see design), cloud models, or network access.
- Clearing librime's user dictionary from the menu (it has its own sync rules).

## Capabilities

### New Capabilities
- `input-memory`: what is recorded, what is never recorded, where it lives, and how the user controls it.

## Impact

- New in `packages/user-data`: `InputMemory`, `InputJournal`, `SentenceFingerprint`, `PrivacyFilter`.
- New in `IMEHostCore`:
  - `SentenceAssembler`;
  - `IntelligenceSettings` (`IntelligenceLearningEnabled`, `IntelligenceJournalEnabled`, `IntelligenceJournalRetentionDays`, `IntelligenceExcludedApps`);
  - a 智能中心 section in `IMEInputController.menu()`.
- `IMEInputController`: on commit, passes text and `client().bundleIdentifier()` to the assembler; flushes on deactivation.
- `docs/project-brief.md`, `docs/technical-design.md`, `docs/intelligence-hub.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`.
