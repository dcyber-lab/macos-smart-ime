## Context

The panel draws `CandidatePanelRow` label, text, and an optional 英/译 tag. English candidates come from `EnglishLexicon` (100,000 wordfreq words plus a display-cased supplement). ECDICT (skywind3000/ECDICT, MIT, commit `bc015ed2`, 2025-03-28) covers 99% of the top 30,000 words and 89% of the top 100,000, but its first listed sense is often not the common one (`good` → 善行, `feature` → 面孔的一部分) and its technical senses are general-purpose (`deploy` → 展开, `iOS` → 国际标准化组织, `roadmap` → 公路交通图). 59 of 182 supplement terms are missing.

## Goals / Non-Goals

**Goals:**
- A short, usually-right Chinese meaning for English candidates.
- Correct workplace meanings for supplement and office terms.

**Non-Goals:**
- Full dictionary entries, phonetics, or example sentences.
- Glosses for translation candidates (the user just typed the Chinese).
- User-editable glosses.

## Decisions

### 1. Generated table from ECDICT
`scripts/english/build-glosses.py` reads ECDICT's `ecdict.csv` (downloaded from the pinned commit and verified by SHA-256, or passed by path), and for each lexicon key writes `key<TAB>gloss` to `en-zh.tsv`:
- Pick the part-of-speech line with the most senses, which tracks the common usage (`good`: a. with 8 senses beats n. with 3 → 好的). ECDICT's `pos` share field would be better, but it is empty for all 26,740 top-30k words it contains. Lines without a part-of-speech prefix (`[网络]`, `[计]`, inflection notes) are ignored unless nothing else exists.
- Strip the part-of-speech prefix and bracketed notes, split senses on `；;，,`, prefer senses of six characters or fewer, and keep at most two.
- The table is MIT-derived and committed, like the other generated resources.

### 2. Hand-written glosses win
`supplement.txt` becomes `display<TAB>gloss`. The generator uses those glosses instead of ECDICT's, and the lexicon reads only the first column. A few common words with wrong workplace senses (e.g. `deploy`) are added to the supplement with their lowercase display form, which keeps their spelling and rank.

### 3. Annotation on `Candidate`
`Candidate` gains `annotation: String?` (default `nil`, so existing call sites are unchanged). `BasicEnglishEngine` and `EnglishAugmentedChineseEngine` set it from `EnglishGlossary` for English word candidates. The panel model copies it into the row, and the view draws it after the candidate text in 12 pt secondary text, truncated to 12 characters, and includes it in the width calculation.

## Risks / Trade-offs

- [Automatic glosses are sometimes off] → Part-of-speech weighting and short-sense preference fix the common cases; supplement overrides handle workplace terms; the English word itself is unchanged.
- [Wider panel] → Glosses are capped at 12 characters.
- [Load time] → About 100,000 short entries parsed once per process with the same byte-level parser as `ChineseEnglishDictionary`; measured in tests.
