## 1. Shared Models and Rime Bridge

- [ ] 1.1 Add `candidatePageIndex` (default 0) to `CompositionState` in `packages/shared-models`
- [ ] 1.2 Fill `candidatePageIndex` from `RimeMenu.page_no` in `RimeBridgeSession.currentState`

## 2. English Engine

- [ ] 2.1 Add `PinyinSyllableSegmenter` with the 418 `luna_pinyin` syllables and a full-segmentation check
- [ ] 2.2 Add unit tests for the segmenter (`women`, `change`, `nihao` segmentable; `hello`, `deploy`, `github` not)
- [ ] 2.3 Add `EnglishAugmentedChineseEngine` wrapping a `ChineseInputEngine`, with eligibility rules (length ≥ 3, `[a-z]` only, first page) and the three-candidate cap
- [ ] 2.4 Implement placement: exact non-pinyin match first, everything else appended after the wrapped engine's candidates
- [ ] 2.5 Implement index mapping for `selectCandidate(at:)`, `highlightCandidate(at:)`, the shifted `selectedCandidateIndex`, and `Space` when an English candidate is highlighted
- [ ] 2.6 Add unit tests with a fake `ChineseInputEngine` covering every scenario in `specs/chinese-mode-english-candidates/spec.md`

## 3. IME Host Integration

- [ ] 3.1 Wrap `RimeBridgeEngine` with `EnglishAugmentedChineseEngine` in `IMEInputController` using `EnglishLexicon.bundled`
- [ ] 3.2 Confirm `swift test` passes and `scripts/ime/build-host.sh` builds the host

## 4. Validation and Docs

- [ ] 4.1 Add a "English Candidates in Chinese Mode" checklist to `docs/ime-manual-validation.md` (`hello`, `women`, `gith`, `nihao`, paging, number keys, arrows + `Space`, `Return`)
- [ ] 4.2 Run the checklist in a real macOS text client
- [ ] 4.3 Update `docs/implementation-log.md` and `docs/technical-design.md` (new `english-engine` → `ChineseInputEngine` decorator boundary)
