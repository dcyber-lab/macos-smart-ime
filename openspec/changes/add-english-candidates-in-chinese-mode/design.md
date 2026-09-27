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
- Offer English translations of the Chinese word being typed (`shujuku` → 数据库 → "database").
- Keep pure pinyin typing unchanged: the first `librime` candidate stays first for pinyin-like input.
- Keep number keys, arrow highlight, `Space`, mouse selection, and paging correct for both candidate kinds.
- Keep all new logic unit-testable without `librime`.

**Non-Goals:**
- Capitalization or brand casing (`GitHub`, `iPhone`); candidates stay lowercase.
- Learning user-typed English words or a user dictionary.
- English spelling correction inside Chinese mode.
- Sentence or phrase translation (needs AI; belongs to the Companion one-key English transformation).
- Translating Chinese candidates other than the first one, or pinyin abbreviations such as `sjk`.
- A user-maintained translation table for missing or imprecise entries (e.g. 周报 → "weekly report"); follow-up change.
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

### 5. Translation data from CC-CEDICT
`scripts/english/build-translations.py` turns a CC-CEDICT release into `zh-en.tsv` (`中文<TAB>gloss1[<TAB>gloss2]`, sorted by key). For each simplified headword of two or more Han characters it:

- Splits glosses on `/` and `; `, removes parentheticals, leading "to " and articles, and keeps the text before the first comma (`Beijing, capital of …` → "Beijing").
- Drops glosses with classifiers (`CL:`), cross-references (`variant of`, `see`, `abbr.`), `sb`/`sth` placeholders, digits, non-ASCII, or more than three words.
- Prefers entries with lowercase pinyin (common nouns) over proper-noun entries, so 苹果 → "apple" rather than "Apple (company)"; keeps at most two unique glosses in dictionary order.

This yields ~81,000 entries (~2 MB). CC-CEDICT is CC-BY-SA 4.0, the same license as the word list; attribution goes in `packages/english-engine/DATA_LICENSE.md`.

Alternatives considered:
- *ECDICT (MIT)*: an English→Chinese dictionary; reversing it gives noisy, many-to-many Chinese→English mappings.
- *Online translation or AI*: violates the no-network, no-AI real-time path rule.

### 6. Translation trigger and placement
Translations are looked up for the **first** `librime` candidate only, when the raw input is eligible (Decision 3), fully pinyin-segmentable, and the candidate is two or more characters. Up to two translations are placed right after the `librime` candidates and before appended English word candidates, deduplicated by text. The merged list is capped at nine entries (dropping from the end), so a full five-candidate Rime page leaves room for two translations and two English words.

Translating only the first candidate keeps the list stable while the user arrows through candidates; translating the highlighted candidate would reshuffle entries under the cursor.

### 7. Performance and loading
Per keystroke: one segmentation pass (input length × 6 set lookups), one `EnglishLexicon` prefix query (binary search plus a scan of matching words), and one dictionary hash lookup. All are in-memory and sub-millisecond. `EnglishLexicon` and `ChineseEnglishDictionary` are loaded once per process when the first input controller is created, not on a keystroke.

## Risks / Trade-offs

- [English candidates add noise while typing pinyin] → Minimum length 3, at most three candidates, pinyin-segmentable input never moves English first, prefix completions are always appended.
- [Words that are valid pinyin (`change`, `china`, ~6% of common words) are not first] → They still appear on the first page after the `librime` candidates, selectable with number keys 6–8.
- [Partial pinyin that happens to be a non-pinyin English word jumps English first, and `Space` commits English] → Rare given the measurement above; covered by unit tests with representative pinyin sequences, and revisit if manual validation shows real collisions.
- [Merged list is longer than the Rime page (up to 8)] → Selection keys 1–9 already cover it; the panel is a single scrolling column.
- [CC-CEDICT glosses are dictionary-style and sometimes off for workplace usage (周报 → "weekly publication", 部署 → "dispose" before "deploy")] → Two glosses are shown; a user translation table is a planned follow-up.
- [~2 MB dictionary increases IME memory and launch time] → Loaded once per process; load time is measured in tests and must stay well under the host's first-activation budget.
- [Index mapping regressions for Chinese selection] → Tests with a fake `ChineseInputEngine` covering select, highlight, `Space`, and paging for every placement.

## Migration Plan

No data or configuration migration. Rollback is constructing `RimeBridgeEngine` directly in `IMEInputController` instead of wrapping it.

## Open Questions

- Should committing an English word next to Chinese text insert CJK–Latin spacing? Deferred; could be a Companion setting or a `transform-engine` concern.
- Should the minimum length or the three-candidate cap become user-tunable once Companion settings exist?
- Should pinyin abbreviations (`sjk` → 数据库) also get translations once there is a reliable way to tell abbreviations from English input?
