## 1. Storage

- [x] 1.1 Move `Usage` out of `CandidateHistory.swift` into its own internal file, unchanged
- [x] 1.2 Add `TranslationMisses` (`UserData`): decayed word counts, processed marks, `lastRun`, bounds, `isEnabled` gate, batched atomic save; tests

## 2. Engine

- [x] 2.1 Add `UserTranslations` (`EnglishEngine`): TSV parse with comments, lookup, reload on modification date, append learned lines under a single header; tests
- [x] 2.2 `EnglishAugmentedChineseEngine`: look up user translations first; record qualifying Chinese commits as misses; tests

## 3. Learner

- [x] 3.1 Add `TermTranslator`, `AppleTermTranslator`, and `TranslationLearningSettings`
- [x] 3.2 Add `TranslationLearner`: due check, candidate selection, acceptance and casing rules, processed marks, hourly retry when languages are missing; tests with a fake translator
- [x] 3.3 Host: shared stores and file URLs in `IMEHostConfiguration`; reload and `runIfDue()` in `activateServer`

## 4. Verification and Docs

- [x] 4.1 Run the unit tests (locally through `swiftc`; CI runs `swift test`)
- [x] 4.2 Update `docs/technical-design.md`, `docs/implementation-log.md`, and `docs/ime-manual-validation.md` (learning checklist with a short interval)
- [ ] 4.3 Walk through the checklist in a real client with the translation languages installed; record the acceptance rate
