## 1. Storage

- [x] 1.1 Add the `UserData` target (`packages/user-data`) with `CandidateHistory`: decayed usages, word and input records, prefix lookup, bounds, JSON load and batched atomic save
- [x] 1.2 Add `UserDataTests`: scoring and decay, prefix order, choices, bounds, save/load round trip, corrupt file

## 2. Ranking and Recording

- [x] 2.1 Add `EnglishLexicon.completions(forPrefix:limit:preferring:)` (learned words first)
- [x] 2.2 `BasicEnglishEngine`: learned completions, record committed lexicon words; tests
- [x] 2.3 `EnglishAugmentedChineseEngine`: picks after the first Chinese candidate, lead rules, Chinese preference over a leading word, recording rules; tests
- [x] 2.4 Host: one shared history at `IMEHostConfiguration.candidateHistoryURL()`, passed to both engines

## 3. Verification and Docs

- [x] 3.1 Run the unit tests and a real-librime check of the learned order (locally through `swiftc`; CI `package.sh` runs `swift test`)
- [x] 3.2 Update `docs/technical-design.md`, `docs/implementation-log.md`, and `docs/ime-manual-validation.md`
- [ ] 3.3 Walk through the candidate learning checklist in a real client
