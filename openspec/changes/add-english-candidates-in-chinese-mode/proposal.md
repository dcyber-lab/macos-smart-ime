## Why

Knowledge workers constantly drop English terms into Chinese text ("用 github 提交", "这个 feature 要 deploy"). Today, Chinese mode only shows `librime` candidates, so typing `hello` or `deploy` produces meaningless pinyin-abbreviation guesses and the user must press `Shift` to switch to English mode and back for every term. Users also often know the Chinese word but want its English equivalent (typing `shujuku` for 数据库 but wanting "database"). The project now has a 30,000-word frequency-ranked `EnglishLexicon`, and a local Chinese–English dictionary lookup is cheap enough for the real-time path, so both kinds of English candidates can be offered directly inside Chinese mode.

## What Changes

- **English word candidates**: in Chinese mode, when the raw input is all lowercase letters, look it up in the project-owned `EnglishLexicon` and merge up to three English word candidates into the Chinese candidate list.
- Place English candidates by how pinyin-like the input is: when the input cannot be segmented into valid pinyin syllables (e.g. `hello`, `github`, `deploy`), an exact English word match goes first; otherwise English candidates follow the `librime` candidates so pinyin input like `women` → 我们 is unchanged.
- **Translation candidates**: when the raw input is valid pinyin and the first `librime` candidate is a Chinese word of two or more characters, look it up in a bundled Chinese→English dictionary generated from CC-CEDICT and show up to two English translations after the `librime` candidates (e.g. `shujuku` → 数据库 … database).
- Cap the merged list at nine candidates so every entry keeps a selection key.
- Only show English candidates on the first candidate page and only for inputs of three or more letters.
- Selecting an English candidate with a number key, `Space` while it is highlighted, or a mouse click commits the English word and clears the `librime` composition.
- Map merged candidate indices back to `librime` page indices so number keys, arrow highlight, and `Space` keep working for Chinese candidates.
- Expose the current candidate page index from `RimeBridge` so English candidates can be limited to the first page.

## Capabilities

### New Capabilities
- `chinese-mode-english-candidates`: English word candidates from the project-owned lexicon and English translations of the first Chinese candidate, merged into the Chinese-mode candidate list, with placement, eligibility, selection, and paging rules.

### Modified Capabilities
- (None)

## Impact

- `packages/english-engine`: new `PinyinSyllableSegmenter` input classifier, `ChineseEnglishDictionary` translation lookup with a bundled `zh-en.tsv` resource (~81,000 entries, ~2 MB, CC-BY-SA 4.0), and an `EnglishAugmentedChineseEngine` that wraps any `ChineseInputEngine`, merges English candidates, and maps selection indices.
- `scripts/english/build-translations.py`: reproducible generator for `zh-en.tsv` from a CC-CEDICT release.
- `packages/shared-models`: `CompositionState` gains a candidate page index; `CandidateSource` gains `englishTranslation`.
- `packages/rime-bridge`: `RimeBridgeSession.currentState` fills the candidate page index from `RimeMenu.page_no`.
- `apps/ime/Sources/IMEHostCore/IMEInputController.swift`: wraps the `RimeBridgeEngine` with `EnglishAugmentedChineseEngine`; key routing is otherwise unchanged.
- No new dependencies. No Rime schema or dictionary changes; English logic stays in `english-engine`.
- Depends on `add-basic-english-mode` (for `EnglishLexicon` and the bundled word list).
