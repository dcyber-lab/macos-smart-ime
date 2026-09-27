## Why

Knowledge workers constantly drop English terms into Chinese text ("用 github 提交", "这个 feature 要 deploy"). Today, Chinese mode only shows `librime` candidates, so typing `hello` or `deploy` produces meaningless pinyin-abbreviation guesses and the user must press `Shift` to switch to English mode and back for every term. The project now has a 30,000-word frequency-ranked `EnglishLexicon`, so English words can be offered directly inside Chinese mode without leaving the real-time path.

## What Changes

- In Chinese mode, when the raw input is all lowercase letters, look it up in the project-owned `EnglishLexicon` and merge up to three English word candidates into the Chinese candidate list.
- Place English candidates by how pinyin-like the input is: when the input cannot be segmented into valid pinyin syllables (e.g. `hello`, `github`, `deploy`), an exact English word match goes first; otherwise English candidates follow the `librime` candidates so pinyin input like `women` → 我们 is unchanged.
- Only show English candidates on the first candidate page and only for inputs of three or more letters.
- Selecting an English candidate with a number key, `Space` while it is highlighted, or a mouse click commits the English word and clears the `librime` composition.
- Map merged candidate indices back to `librime` page indices so number keys, arrow highlight, and `Space` keep working for Chinese candidates.
- Expose the current candidate page index from `RimeBridge` so English candidates can be limited to the first page.

## Capabilities

### New Capabilities
- `chinese-mode-english-candidates`: English word candidates from the project-owned lexicon, merged into the Chinese-mode candidate list, with placement, eligibility, selection, and paging rules.

### Modified Capabilities
- (None)

## Impact

- `packages/english-engine`: new `PinyinSyllableSegmenter` input classifier and an `EnglishAugmentedChineseEngine` that wraps any `ChineseInputEngine`, merges English candidates, and maps selection indices.
- `packages/shared-models`: `CompositionState` gains a candidate page index.
- `packages/rime-bridge`: `RimeBridgeSession.currentState` fills the candidate page index from `RimeMenu.page_no`.
- `apps/ime/Sources/IMEHostCore/IMEInputController.swift`: wraps the `RimeBridgeEngine` with `EnglishAugmentedChineseEngine`; key routing is otherwise unchanged.
- No new dependencies. No Rime schema or dictionary changes; English logic stays in `english-engine`.
- Depends on `add-basic-english-mode` (for `EnglishLexicon` and the bundled word list).
