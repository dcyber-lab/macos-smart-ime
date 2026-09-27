## 1. Lexicon

- [x] 1.1 Regenerate `wordlist.txt` with 100,000 words (`scripts/english/build-wordlist.py --size 100000`) and update `DATA_LICENSE.md`
- [x] 1.2 Add `supplement.txt` with display-cased technical and office terms
- [x] 1.3 Give `EnglishLexicon` lowercase keys, display forms, and supplement ranking (`index + 2000`); keep `contains` and prefix lookup case-insensitive
- [x] 1.4 Add tests for coverage, display casing, supplement ranking, common-word ranking, and load time

## 2. Candidate Rules

- [x] 2.1 Translate the first multi-character `librime` candidate whenever no exact English word is placed first
- [x] 2.2 Promote the top English completion to position 2 for 4+ letter non-pinyin input
- [x] 2.4 Restrict Chinese-mode English candidates to common words and the supplement, allowing rare words only for 5+ letter non-pinyin input
- [x] 2.3 Update `EnglishAugmentedChineseEngineTests` for every scenario in `specs/english-candidates-while-typing/spec.md`

## 3. Verification and Docs

- [x] 3.1 Probe real librime for `shujuk`, `sjk`, `huiy`, `featu`, `gith`, `dep`, `kube`, `json`, `refac`, `github`, `ios`
- [x] 3.2 Run `scripts/ime/dev-cycle.sh` (smoke test must pass)
- [x] 3.3 Update `docs/implementation-log.md`, the English checklist in `docs/ime-manual-validation.md`, and `docs/technical-design.md`
