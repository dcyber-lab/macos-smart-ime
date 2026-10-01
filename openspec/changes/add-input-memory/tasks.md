## 1. Memory and Privacy (`packages/user-data`)

- [x] 1.1 `PrivacyFilter`: sentence rules (digits, email, URL, token) and app rules (defaults, user list, unknown ID), with tests
- [x] 1.2 `SentenceFingerprint`: normalization and salted HMAC-SHA256, with tests
- [x] 1.3 `InputMemory`: app language profiles and fingerprints with decay, bounds, 0600 file, background save, `clear()`, with tests
- [x] 1.4 `InputJournal`: daily JSONL append off the main thread, 0700/0600, excluded from backup, retention, `clear()`, with tests

## 2. Capture (`IMEHostCore`)

- [x] 2.1 `SentenceAssembler`: per-app buffers, boundaries (punctuation, Return, 10 s, focus/app change), last 5 sentences in memory, with tests
- [x] 2.2 `IntelligenceSettings`: `IntelligenceLearningEnabled` (default false), `IntelligenceJournalEnabled` (default true), `IntelligenceJournalRetentionDays` (default 30), `IntelligenceExcludedApps`
- [x] 2.3 Wire `IMEInputController`: feed commits with `client().bundleIdentifier()`, skip on secure input, flush on deactivation

## 3. Controls

- [x] 3.1 智能中心 menu section: learning toggle, journal toggle, per-app exclusion, view, clear (with confirmation)
- [x] 3.2 Learning page (HTML, 0600): summary plus searchable journal

## 4. Verification and Docs

- [ ] 4.1 Unit tests locally (done) and in CI; measure commit-path cost with learning on vs off (done: 0.4 vs 3.9 µs)
- [x] 4.2 Update `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`
- [ ] 4.3 Live check: enable, type in two apps, view and search the journal, exclude an app, turn the journal off, clear
