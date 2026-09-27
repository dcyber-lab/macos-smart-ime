## Context

Chinese mode routes every key to `RimeBridgeEngine` (`luna_pinyin`, page size 5). `IMEInputController` shows `CompositionState.candidates` in `IMKCandidates` and already intercepts number keys (`selectCandidate(at:)`) and arrow keys (`highlightCandidate(at:)`) before `librime` sees them; `Space`, `Return`, paging and letters go to `librime`. English words are only reachable by toggling to English mode with `Shift`.

`add-basic-english-mode` added `EnglishLexicon`: 30,000 frequency-ordered words, loaded once per process, with binary-search prefix lookup. Rules that constrain this change:

- English logic must live in project-owned modules, not in `librime` schemas or dictionaries.
- Nothing slow may run in the key-by-key path.
- `librime` stays the Chinese input core; we do not reimplement pinyin conversion.

Measured against the bundled lexicon: of the top 5,000 English words with three or more letters, 292 (~6%) can be fully segmented into valid pinyin syllables (`women`, `change`, `china`, `like`, `time`). The other ~94% (`hello`, `deploy`, `github`, `feature`, `the`) cannot.

## Goals / Non-Goals

**Goals:**
- Offer English word candidates inside Chinese mode without a mode toggle.
- Keep pure pinyin typing unchanged: the first `librime` candidate stays first for pinyin-like input.
- Keep number keys, arrow highlight, `Space`, mouse selection, and paging correct for both candidate kinds.
- Keep all new logic unit-testable without `librime`.

**Non-Goals:**
- Capitalization or brand casing (`GitHub`, `iPhone`); candidates stay lowercase.
- Learning user-typed English words or a user dictionary.
- English spelling correction inside Chinese mode.
- A user-facing on/off setting (belongs to a future Companion settings change).
- English candidates on candidate pages after the first.
- Automatic spacing between Chinese and English text.

## Decisions

### 1. Decorator engine in `english-engine`
Add `EnglishAugmentedChineseEngine: ChineseInputEngine` that wraps another `ChineseInputEngine` (the `RimeBridgeEngine` in production, a fake in tests). It forwards keys to the wrapped engine, merges English candidates into the returned `CompositionState`, and translates merged candidate indices back to wrapped-engine indices. `IMEInputController` only changes where it constructs the Chinese engine.

Alternatives considered:
- *Rime `table_translator@melt_eng` English dictionary*: native ranking and paging, but moves English logic into Rime data, contradicting the project rule, and cannot share `EnglishLexicon` or its exclusion list.
- *Merge inside `IMEInputController`*: puts English ranking policy in the host and makes it hard to test without InputMethodKit.

### 2. Placement by pinyin segmentability
A small `PinyinSyllableSegmenter` checks whether the raw input can be fully segmented into valid pinyin syllables (418-syllable set from `luna_pinyin`, dynamic programming over at most six-letter syllables).

- Input **not** segmentable and an exact English word (`hello`, `deploy`, `the`): the exact word is placed **first**, before the `librime` candidates.
- Everything else (segmentable input such as `women`, or prefix-only completions such as `gith` → `github`): English candidates are **appended after** the `librime` candidates on the page.
- At most three English candidates: the exact match, if any, then frequency-ordered completions.

Alternatives considered:
- *Always append*: never disturbs pinyin, but `hello` + `Space` would commit a meaningless abbreviation guess.
- *Always first*: breaks everyday pinyin such as `women` → 我们 and `men` → 们.
- *Use `librime` candidate weights*: `RimeCandidate` does not expose weights through the C API.

This is a classifier deciding where English goes, not pinyin conversion, so it does not duplicate `librime`.

### 3. Eligibility
English candidates are computed only when the raw input is three or more characters, all `[a-z]`, and the wrapped engine reports the first candidate page. Inputs with delimiters (`'`), uppercase, digits, or Rime prefixes (`` ` ``, `P:`, `C:`) are ignored. `RimeBridgeSession.currentState` gains `candidatePageIndex` from `RimeMenu.page_no`, carried on `CompositionState`.

### 4. Selection and highlight mapping
The merged list is modeled as entries of `.chinese(pageIndex)` or `.english(word)`.

- `selectCandidate(at:)`: Chinese entries forward the mapped page index; English entries commit the word (no trailing space), reset the wrapped engine, and clear the composition.
- `highlightCandidate(at:)`: Chinese entries forward to the wrapped engine and clear any English highlight; English entries set a local highlight that is reported as `selectedCandidateIndex`.
- The default highlight is merged index 0. When index 0 is English, `Space` is intercepted and commits that word; otherwise `Space` goes to `librime` as today.
- Any other key clears the English highlight and forwards to the wrapped engine, then the list is re-merged. `Return` still commits the raw input through `librime`.
- The wrapped engine's `selectedCandidateIndex` is shifted by the number of English entries placed before the Chinese candidates.
- Mouse selection (`candidateSelected`) already commits the clicked text and resets engines, so it needs no mapping.

### 5. Performance
Per keystroke: one segmentation pass (input length × 6 set lookups) and one `EnglishLexicon` prefix query (binary search plus a scan of matching words). Both are in-memory and sub-millisecond; the lexicon is already loaded for English mode.

## Risks / Trade-offs

- [English candidates add noise while typing pinyin] → Minimum length 3, at most three candidates, pinyin-segmentable input never moves English first, prefix completions are always appended.
- [Words that are valid pinyin (`change`, `china`, ~6% of common words) are not first] → They still appear on the first page after the `librime` candidates, selectable with number keys 6–8.
- [Partial pinyin that happens to be a non-pinyin English word jumps English first, and `Space` commits English] → Rare given the measurement above; covered by unit tests with representative pinyin sequences, and revisit if manual validation shows real collisions.
- [Merged list is longer than the Rime page (up to 8)] → Selection keys 1–9 already cover it; the panel is a single scrolling column.
- [Index mapping regressions for Chinese selection] → Tests with a fake `ChineseInputEngine` covering select, highlight, `Space`, and paging for every placement.

## Migration Plan

No data or configuration migration. Rollback is constructing `RimeBridgeEngine` directly in `IMEInputController` instead of wrapping it.

## Open Questions

- Should committing an English word next to Chinese text insert CJK–Latin spacing? Deferred; could be a Companion setting or a `transform-engine` concern.
- Should the minimum length or the three-candidate cap become user-tunable once Companion settings exist?
