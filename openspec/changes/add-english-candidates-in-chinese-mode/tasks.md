## 1. Shared Models and Rime Bridge

- [x] 1.1 Add `candidatePageIndex` (default 0) to `CompositionState` and `englishTranslation` to `CandidateSource` in `packages/shared-models`
- [x] 1.2 Fill `candidatePageIndex` from `RimeMenu.page_no` in `RimeBridgeSession.currentState`

## 2. English Engine

- [x] 2.1 Add `PinyinSyllableSegmenter` with the `luna_pinyin` syllables (minus the `xx` marker, plus `lue`/`nue`) and a full-segmentation check
- [x] 2.2 Add unit tests for the segmenter (`women`, `change`, `nihao` segmentable; `hello`, `deploy`, `github` not)
- [x] 2.3 Add `scripts/english/build-translations.py` and generate `zh-en.tsv` from CC-CEDICT; add CC-CEDICT attribution to `packages/english-engine/DATA_LICENSE.md`
- [x] 2.4 Add `ChineseEnglishDictionary` (bundled load once per process, lookup by Chinese word) with tests for 数据库, 苹果, 北京, and load time
- [x] 2.5 Add `EnglishAugmentedChineseEngine` wrapping a `ChineseInputEngine`, with eligibility rules (length ≥ 3, `[a-z]` only, first page) and the three-candidate cap
- [x] 2.6 Implement placement: exact non-pinyin match first, then `librime` candidates, then up to two translations of the first candidate, then English words; dedupe by text and cap at nine
- [x] 2.7 Implement index mapping for `selectCandidate(at:)`, `highlightCandidate(at:)`, the shifted `selectedCandidateIndex`, and `Space` when an English candidate is highlighted
- [x] 2.8 Add unit tests with a fake `ChineseInputEngine` covering every scenario in `specs/chinese-mode-english-candidates/spec.md`
- [x] 2.9 Show the raw input as the composition text for non-pinyin input that has no converted part (e.g. `good` instead of "go o d"), with tests

## 3. IME Host Integration

- [x] 3.1 Wrap `RimeBridgeEngine` with `EnglishAugmentedChineseEngine` in `IMEInputController` using `EnglishLexicon.bundled` and `ChineseEnglishDictionary.bundled`
- [x] 3.2 Confirm `swift test` passes and `scripts/ime/build-host.sh` builds the host

## 4. Validation and Docs

- [x] 4.1 Add a "English Candidates in Chinese Mode" checklist to `docs/ime-manual-validation.md` (`hello`, `women`, `gith`, `nihao`, `shujuku` → database, paging, number keys, arrows + `Space`, `Return`)
- [ ] 4.2 Run the checklist in a real macOS text client
- [x] 4.3 Update `docs/implementation-log.md` and `docs/technical-design.md` (new `english-engine` → `ChineseInputEngine` decorator boundary)
