## Why

Translation candidates miss or mistranslate most developer terms. `neihekongj` → 内核空间 shows no English at all, 内核 gives "core", 容器 "receptacle", 队列 "formation", 中断 "cut short". `zh-en.tsv` comes only from CC-CEDICT, a general dictionary: it lacks many technical words (用户空间, 协程, 微服务), and the build script keeps only a headword's first two glosses, so the "(computing) kernel" sense CC-CEDICT does have is dropped.

A prototype on 138 common developer terms scored 73 correct in first place today. Listing CC-CEDICT's computing sense first raised that to 81, filling gaps from ECDICT's `[计]` senses raised it to 85, and a hand-written table covered the rest.

## What Changes

- `zh-en.tsv` is built from three layers, highest precedence first:
  1. A project-authored table of common developer terms (`packages/english-engine/Data/zh-en-supplement.tsv`), e.g. 内核空间 → kernel space. It replaces the whole entry.
  2. CC-CEDICT, with glosses marked "(computing)" and the like listed before general glosses instead of being dropped (内核 → kernel, core).
  3. For headwords neither layer has, ECDICT's `[计]` (computing) senses, reversed and limited to one common English word or phrase (源文件 → source file).
- ECDICT's other senses are not used: reversing them gives wrong everyday translations (开心 → open core, 喜欢 → choose to).
- The build never reads rime-ice data, so the committed table contains nothing derived from GPL-3.0 material.
- No Swift changes: the engine still looks up the first Chinese candidate and shows at most two translations.

## Capabilities

### New Capabilities
- `chinese-english-translations`: where translation candidates come from, their precedence, and the developer-term coverage they guarantee.

### Modified Capabilities
- (None)

## Impact

- `scripts/english/build-translations.py`: three-layer build; reads the pinned ECDICT (shared with `build-glosses.py`) and the supplement.
- `packages/english-engine/Data/zh-en-supplement.tsv`: new, hand-written, several hundred terms.
- `packages/english-engine/Sources/EnglishEngine/Resources/zh-en.tsv`: regenerated, about 88,600 → 125,000 entries (2.2 → 3.4 MB).
- `packages/english-engine/Tests`: bundled-table assertions for developer terms and unchanged everyday words.
- `packages/english-engine/DATA_LICENSE.md`, `docs/technical-design.md`, `docs/implementation-log.md`, `docs/ime-manual-validation.md`.
