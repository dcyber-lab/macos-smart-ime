## Why

English candidates never learn from the user. In Chinese mode `gith` always shows 1.个 2.GitHub no matter how often the user presses 2, `hello` always puts "hello" first even for a user who keeps picking 何乐, and English completions in both modes follow corpus frequency only. The user should find their usual choice at the top, reachable with Space, after using it a few times.

Chinese candidates already learn: librime records every commit in `smartime_pinyin.userdb` and ranks those words first. Checked against a copy of a real user dictionary: `he` → 合, `shi` → 时, `gj` → 根据, `sj` → 数据 move to the top after being picked. This change does not touch Chinese ranking.

## What Changes

- Keep a small local record of the user's picks (`candidate-history.json` in the input method's Application Support folder): English words the user commits, and per typed input which English candidate or Chinese was picked. Counts decay with a 30-day half-life so the ranking follows changing habits.
- English completions in both modes list the user's own words (most used first) before corpus-ranked words. In English mode the typed text stays first so Space still commits it.
- In Chinese mode an English candidate picked before for the same input moves right after the first Chinese candidate; it becomes candidate 1 (Space commits it) once it has been picked more often than Chinese for that input, and for pinyin input only after two picks.
- A non-pinyin English word that normally leads (`hello`) steps back to position 2 once the user has picked Chinese for that input more often than the word.
- New `UserData` package (`packages/user-data`, planned in the layout) owns storage; `EnglishEngine` owns ranking; the host creates one shared history per process.

## Capabilities

### New Capabilities
- `candidate-learning`: what is recorded, how picks reorder English candidates in both modes, and how the record is stored.

### Modified Capabilities
- (None)

## Impact

- `packages/user-data`: new `UserData` target with `CandidateHistory` and tests.
- `packages/english-engine`: `EnglishAugmentedChineseEngine` and `BasicEnglishEngine` take an optional history, rank with it, and record commits.
- `apps/ime/Sources/IMEHostCore`: one shared history, file path in `IMEHostConfiguration`.
- `Package.swift`: new target and test target.
- Privacy: only lexicon words and typed inputs of English-eligible compositions are stored, never Chinese text or arbitrary strings; local only, deleting the file resets it.
