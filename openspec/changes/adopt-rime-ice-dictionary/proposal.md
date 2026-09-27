## Why

Chinese candidates come from the minimal `luna_pinyin` data (29,000 entries plus the essay corpus), a traditional-Chinese dictionary run through a simplifier. It misses current vocabulary: `yunyuansheng` gives 晕原声 instead of 云原生, `neijuan` gives 内眷 instead of 内卷, `fupan` gives 覆盘 instead of 复盘. The rime-ice (雾凇拼音) dictionaries are simplified, frequency-weighted, actively maintained (last commit 2026-09-25), and produced the expected words for all three in a prototype.

## What Changes

- Add a `smartime_pinyin` schema (simplified full pinyin, same speller rules as `luna_pinyin`, no Lua, no Rime English dictionary) whose dictionary imports rime-ice's `8105`, `base`, `ext`, and `others` tables (about 890,000 entries).
- Fetch those four tables and rime-ice's license from a pinned commit at build time, verified by SHA-256, into `build/rime-data/` instead of committing 28 MB of GPL-3.0 data.
- Assemble the Rime shared data directory at build time from the existing minimal data, the project's schema files, and the fetched tables, and point the host at it.
- Make `smartime_pinyin` the default schema; keep `luna_pinyin` in the schema list as a fallback.
- Precompile the dictionaries with `rime_deployer` during install so the first keystroke after an install does not wait for a Rime deploy.

## Capabilities

### New Capabilities
- `chinese-dictionary`: which Chinese dictionary the host uses, how it is obtained and verified, and when it is compiled.

### Modified Capabilities
- (None)

## Impact

- New `third_party/librime-data/smartime/` (project-authored schema, dictionary manifest, default list), `scripts/rime/fetch-rime-ice.sh`, and `scripts/rime/assemble-shared-data.sh`.
- `scripts/ime/build-host.sh` assembles shared data; `scripts/ime/install-host.sh` runs `rime_deployer --build` (Homebrew librime already provides it).
- `project.yml` / generated Xcode project: `RIME_SHARED_DATA_DIR` points at `build/rime-data/shared`.
- `IMEHostConfiguration.defaultSchemaID` becomes `smartime_pinyin`. Learned words in the old `luna_pinyin` user dictionary do not carry over.
- Licensing: rime-ice data is GPL-3.0. It is downloaded at build time, not committed; distributing a build that includes it must follow GPL-3.0.
- Builds need network access the first time (the fetched files are cached under `build/`).
