## Why

English candidates show only the English word, so users who are unsure of a word (`deploy` vs `deployed`, or what `roadmap` means) cannot tell candidates apart without leaving the input method. Showing a short Chinese meaning next to each English candidate lets them pick the right word in place.

## What Changes

- Show a short Chinese gloss next to English word candidates in both Chinese mode and English mode (e.g. `deploy 部署`, `meeting 会议`). Translation candidates (`译`) do not get a gloss.
- Generate a bundled `en-zh.tsv` gloss table for the English lexicon from ECDICT (MIT) at a pinned commit, choosing the most frequent part of speech and at most two short senses.
- Give every supplement term a hand-written workplace gloss (`GitHub 代码托管平台`, `OKR 目标与关键成果`), which overrides ECDICT; add a few common office words whose ECDICT sense is wrong for work (`deploy`).
- `Candidate` gains an optional `annotation`; the candidate panel draws it in small secondary text after the candidate.

## Capabilities

### New Capabilities
- `english-candidate-glosses`: which English candidates get a Chinese gloss, where it comes from, and how it is shown.

### Modified Capabilities
- (None)

## Impact

- `packages/shared-models`: `Candidate.annotation`.
- `packages/english-engine`: `EnglishGlossary`, `en-zh.tsv`, supplement format `display<TAB>gloss`, both English engines set annotations.
- `scripts/english/build-glosses.py`: ECDICT download (pinned, SHA-256) and table generation.
- `apps/ime/Sources/IMEHostCore`: panel model and drawing show annotations.
- Adds roughly 100,000 glosses (about 2 MB) loaded once per process.
