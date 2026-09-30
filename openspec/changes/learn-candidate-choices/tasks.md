## 1. Storage

- [ ] 1.1 Add the `UserData` target (`packages/user-data`) with `CandidateHistory`: decayed usages, word and input records, prefix lookup, bounds, JSON load and batched atomic save
- [ ] 1.2 Add `UserDataTests`: scoring and decay, prefix order, choices, bounds, save/load round trip, corrupt file

## 2. Ranking and Recording

- [ ] 2.1 Add `EnglishLexicon.completions(forPrefix:limit:preferring:)` (learned words first)
- [ ] 2.2 `BasicEnglishEngine`: learned completions, record committed lexicon words; tests
- [ ] 2.3 `EnglishAugmentedChineseEngine`: picks after the first Chinese candidate, lead rules, Chinese preference over a leading word, recording rules; tests
- [ ] 2.4 Host: one shared history at `IMEHostConfiguration.candidateHistoryURL()`, passed to both engines

## 3. Verification and Docs

- [ ] 3.1 Run the unit tests (CI `package.sh` runs `swift test`) and a real-librime check of the learned order
- [ ] 3.2 Update `docs/technical-design.md`, `docs/implementation-log.md`, and `docs/ime-manual-validation.md`
