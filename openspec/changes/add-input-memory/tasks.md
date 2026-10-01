## 1. Memory and Privacy (`packages/user-data`)

- [ ] 1.1 `PrivacyFilter`: sentence rules (digits, email, URL, token) and app rules (defaults, user list, unknown ID), with tests
- [ ] 1.2 `SentenceFingerprint`: normalization and salted HMAC-SHA256, with tests
- [ ] 1.3 `InputMemory`: app language profiles and fingerprints with decay, bounds, 0600 file, background save, `clear()`, with tests

## 2. Capture (`IMEHostCore`)

- [ ] 2.1 `SentenceAssembler`: per-app buffers, boundaries (punctuation, Return, 10 s, focus/app change), last 5 sentences in memory, with tests
- [ ] 2.2 `IntelligenceSettings`: `IntelligenceLearningEnabled` (default false), `IntelligenceExcludedApps`
- [ ] 2.3 Wire `IMEInputController`: feed commits with `client().bundleIdentifier()`, skip on secure input, flush on deactivation

## 3. Controls

- [ ] 3.1 智能中心 menu section: learning toggle, per-app exclusion, view, clear (with confirmation)
- [ ] 3.2 Learning summary (HTML, no sentence text)

## 4. Verification and Docs

- [ ] 4.1 Unit tests locally and in CI; measure commit-path cost with learning on vs off
- [ ] 4.2 Update `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`
- [ ] 4.3 Live check: enable, type in two apps, view summary, exclude an app, clear
