## 1. Build Script

- [ ] 1.1 Move ECDICT download, SHA-256 check, and `--ecdict` handling into `scripts/english/ecdict_source.py`; `build-glosses.py` imports it and still produces an identical `en-zh.tsv`
- [ ] 1.2 `build-translations.py`: consider every cleaned CC-CEDICT gloss and list computing glosses first (marker rules in design 2)
- [ ] 1.3 `build-translations.py`: ECDICT `[计]` gap fill with the filters in design 3
- [ ] 1.4 `build-translations.py`: read and validate the supplement (design 4); supplement entries replace lower layers; print entry counts per layer and the CC-CEDICT release

## 2. Supplement

- [ ] 2.1 Write `packages/english-engine/Data/zh-en-supplement.tsv` covering the design 4 domains, including the terms CC-CEDICT gets wrong and overrides for 测试, 指标, 标签
- [ ] 2.2 Check every supplement term against the generated table: no typos, everyday sense kept second where it applies

## 3. Table and Tests

- [ ] 3.1 Regenerate `zh-en.tsv`; review the changes among the 3,000 most common CC-CEDICT headwords (entry count and diff summary in the implementation log)
- [ ] 3.2 `ChineseEnglishDictionaryTests`: bundled-table assertions for each spec scenario (内核空间, 内核, 源文件, 仓库, 问题, 开心); keep the load-time bound; record parse time before and after
- [ ] 3.3 Run the unit tests (locally through `swiftc`; CI runs `swift test`)

## 4. Docs

- [ ] 4.1 Update `packages/english-engine/DATA_LICENSE.md` (three sources for `zh-en.tsv`) and `docs/technical-design.md`
- [ ] 4.2 Add translation checks (`neihekongj`, `neihe`, `rongqi`) to `docs/ime-manual-validation.md`; append to `docs/implementation-log.md`
- [ ] 4.3 Walk through the translation checks in a real client
