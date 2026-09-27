## 1. Data

- [x] 1.1 Change `supplement.txt` to `display<TAB>gloss`, write workplace glosses for every term, and add office words whose ECDICT sense is wrong (e.g. `deploy`); make `EnglishLexicon` read only the first column
- [x] 1.2 Add `scripts/english/build-glosses.py` (pinned ECDICT with SHA-256, part-of-speech weighting, short senses, supplement overrides) and generate `en-zh.tsv`; update `DATA_LICENSE.md`
- [x] 1.3 Add `EnglishGlossary` with bundled loading and tests (good, deploy, GitHub, load time)

## 2. Candidates and Panel

- [x] 2.1 Add `Candidate.annotation` (default `nil`)
- [x] 2.2 Set annotations for English word candidates in `BasicEnglishEngine` and `EnglishAugmentedChineseEngine`, not for translations; add tests
- [x] 2.3 Carry annotations into `CandidatePanelRow`, draw them truncated to 12 characters, include them in sizing; add tests

## 3. Verification and Docs

- [x] 3.1 Render panel previews with glosses in light and dark for review
- [x] 3.2 Run `scripts/ime/dev-cycle.sh`
- [x] 3.3 Update `docs/implementation-log.md`, `docs/technical-design.md`, and the English checklist in `docs/ime-manual-validation.md`
