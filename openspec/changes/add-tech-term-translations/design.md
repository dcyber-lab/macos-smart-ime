## Context

`ChineseEnglishDictionary` loads `zh-en.tsv` once per process. `EnglishAugmentedChineseEngine` looks up librime's first candidate when it has two or more characters and appends up to two translations after the Chinese candidates. `build-translations.py` generates the table from the latest CC-CEDICT release. For each headword it cleans the glosses (parentheticals removed, three words at most, cross-references rejected) and keeps the first two. `build-glosses.py` already downloads a pinned ECDICT for the English-to-Chinese glosses.

## Goals / Non-Goals

**Goals:**
- Common developer terms get the English a developer would type, in first place.
- Everyday words keep their current translations.
- Hand-written terms can be added without touching code.

**Non-Goals:**
- Swift changes: lookup rules, the two-translation limit, and translating non-first candidates stay as they are.
- Single-character headwords (栈, 锁): the engine does not translate them.
- Composing translations from parts (内核 + 空间): it produces wrong English such as "core space".
- Using rime-ice data in the build (see decision 5).

## Decisions

### 1. Layer order: supplement, then CC-CEDICT, then ECDICT `[计]`
CC-CEDICT is the most reliable source for everyday words, so it stays the base. The supplement goes above it, because only hand-written entries can fix technical words CC-CEDICT gets wrong (中断 → cut short). ECDICT only fills headwords the other two lack.

Alternative considered: putting ECDICT's reversed senses first. In the prototype this changed 294 of the 3,000 most common words, many for the worse (问题 → sieve problem, 删除 → kill, 打开 → on).

### 2. CC-CEDICT: computing glosses first
A gloss whose marker starts with `(computing`, `(computer`, or `(software`, or is exactly `(Internet)`, is a computing gloss. `(Internet slang)` is not. When the same gloss also appears plainly (进程: "process" and "(computing) process"), it counts as a computing gloss.
- For each headword, computing glosses keep their relative order and go first, then the other glosses; the first two are kept.
- Every cleaned gloss is considered, not only the first two.
- Effect in the prototype: 17 of the 3,000 most common words changed, mostly for the better (引用 → reference, 界面 → interface, 升级 → upgrade). The worse ones, 测试 → beta and 指标 → pointer, are overridden by the supplement.

### 3. ECDICT `[计]` gap fill
For every ECDICT row whose `[计]` line lists a Chinese sense in its first two positions, that sense becomes a candidate headword. A candidate is kept only if all of these hold:
- The English is lowercase, has no hyphen, has at most three words, and every word is in `wordlist.txt`'s top 50,000.
- The row is not an inflection (its exchange field has no `0:`).
- The headword is two or more Han characters and does not end in 的, 了, 着, 过, 地, or 得.

Among the qualifying English for a headword, the most frequent in wordfreq wins, with earlier senses ranked higher, and only one is kept. In the prototype this added about 36,800 headwords. A spot check of 60 found about 85% usable. ECDICT's computing terms are sometimes dated (compiler → 编译程序, not 编译器), which is why this layer only fills gaps.

### 4. Supplement format and scope
- `packages/english-engine/Data/zh-en-supplement.tsv`, lines of `chinese<TAB>english[<TAB>english]`. Lines starting with `#` are section headings or comments. It sits outside `Resources` because it is build input and is not bundled.
- The build fails on:
  - a headword shorter than two Han characters
  - a duplicate headword
  - more than two translations
  - an empty field
- A headword with a common everyday meaning keeps that meaning second: 仓库 → repository, warehouse; 镜像 → image, mirror.
- Coverage: kernel/OS, concurrency, memory, data structures and algorithms, languages and compilers, databases, networking, cloud and containers, DevOps and release, security, Git and code review, frontend/backend/mobile, testing, observability, AI/ML, and product/engineering process. It includes the terms CC-CEDICT gets wrong or lists badly.

### 5. No rime-ice data in the build
The prototype kept ECDICT fills only for words in rime-ice's vocabulary, to keep the table small. rime-ice is GPL-3.0, and the repository deliberately keeps its tables out and fetches them at build time. Filtering the committed `zh-en.tsv` by rime-ice's word selection could make the table a derivative of it. Without the filter, the table grows by about 1.1 MB, and translation quality is the same because lookups only ever hit librime's first candidate.

### 6. Shared ECDICT loader
`build-glosses.py`'s pinned URL, SHA-256 check, and `--ecdict` override move into `scripts/english/ecdict_source.py`, which both scripts import. `build-translations.py` gains `--ecdict` and `--supplement`, and prints the entry count per layer.

## Risks / Trade-offs

- [Bigger table slows startup] → About 125,000 entries (3.4 MB), parsed once per process. The existing load-time test keeps its bound. Parse time is measured before and after.
- [Supplement overrides an everyday word with its technical sense] → Only terms whose technical sense is the common one are overridden, and the everyday sense stays second.
- [ECDICT fills contain odd translations (呼叫者 → call subscriber)] → They appear only for headwords that had no translation, after the Chinese candidates.
- [CC-CEDICT is not pinned] → Unchanged from today. The build prints the release date, and the implementation log records it.

## License

`zh-en.tsv` stays CC-BY-SA 4.0, as a derivative of CC-CEDICT. It also includes ECDICT (MIT) and project-authored entries, which may be combined into a CC-BY-SA work. `DATA_LICENSE.md` lists all three sources.
