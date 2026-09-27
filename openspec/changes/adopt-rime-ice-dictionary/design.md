## Context

`RimeBridgeRuntime` reads shared data from `RimeSharedDataDirectory` (Info.plist, set from `RIME_SHARED_DATA_DIR` = `third_party/librime-data/minimal`) and keeps user data and compiled tables in `~/Library/Application Support/SmartIMEHost/Rime`. The host selects `IMEHostConfiguration.defaultSchemaID` (`luna_pinyin`) and runs Rime maintenance when it starts.

Prototype results (Homebrew librime 1.16.1, `rime_deployer --build`):

- Compiling `smartime_pinyin` (8105 + base + ext + others) plus `luna_pinyin` took 3.8 s; `smartime_pinyin.table.bin` is 28 MB (`luna_pinyin` 8 MB).
- Real-librime comparison: 云原生, 内卷, 复盘 come first with rime-ice; `luna_pinyin` gives 晕原声, 内眷, 覆盘. Both give 打工人, 躺平, 上线, 灰度, 周报.

## Goals / Non-Goals

**Goals:**
- Modern simplified Chinese vocabulary by default.
- Reproducible, verified dictionary inputs without committing large GPL data.
- No Rime deploy pause on the first keystroke after an install.

**Non-Goals:**
- rime-ice's Lua features (dates, calculator, pinning), its English dictionaries (English stays in `english-engine`), emoji/OpenCC filters, or fuzzy-pinyin rules.
- The `tencent` (980,000 entries, 17 MB) and `41448` rare-character tables; they can be added to the manifest later.
- Bundling Rime data inside the app for distribution; the host still reads shared data from the build tree, as today.
- Migrating learned words from the `luna_pinyin` user dictionary.

## Decisions

### 1. Own schema, rime-ice tables only
`smartime_pinyin.schema.yaml` copies `luna_pinyin`'s processors, segmentors, and speller algebra, drops the cangjie reverse lookup and the traditional/simplified switches, and uses `script_translator` with dictionary `smartime_pinyin`. `smartime_pinyin.dict.yaml` imports `cn_dicts/8105`, `cn_dicts/base`, `cn_dicts/ext`, `cn_dicts/others` (the same order rime-ice uses, so earlier tables win on duplicates).

Alternative considered: ship rime-ice's own `rime_ice` schema. It depends on librime-lua and rime-ice's English tables, which conflicts with keeping English logic in `english-engine`, and our bridge does not load Rime plugins.

### 2. Fetch at build time from a pinned commit
`scripts/rime/fetch-rime-ice.sh` downloads the four tables and `LICENSE` from `raw.githubusercontent.com/iDvel/rime-ice/3aea6d3694fb3d94ec663641f021f788822897ad/...` into `build/rime-data/rime-ice/`, verifies each file's SHA-256, and skips the download when verified files are already present. Updating rime-ice means changing the commit and the checksums in one place.

Alternatives considered: committing the tables (28 MB of GPL-3.0 data in the repository history) or a git submodule (the whole rime-ice repository and history).

### 3. Assembled shared data directory
`scripts/rime/assemble-shared-data.sh` builds `build/rime-data/shared/` from `third_party/librime-data/minimal/*`, then `third_party/librime-data/smartime/*` (which overrides `default.yaml` to list `smartime_pinyin` first), then `cn_dicts/` from the fetched tables. `build-host.sh` runs fetch and assemble before building; `RIME_SHARED_DATA_DIR` points at `$(SRCROOT)/build/rime-data/shared`.

### 4. Precompile during install
After stopping the running host, `install-host.sh` runs `rime_deployer --build <user data> <shared data> <user data>/build` as the target user. The host's own startup maintenance then finds up-to-date tables. If `rime_deployer` is missing, install warns and the host compiles on first use (about 4 s).

### 5. Default schema
`IMEHostConfiguration.defaultSchemaID` becomes `smartime_pinyin`. `luna_pinyin` stays in `schema_list`, so Rime's schema switcher can still reach it.

## Risks / Trade-offs

- [GPL-3.0 data] → Not committed; fetched per build; the docs state that distributing a build with it must follow GPL-3.0.
- [Build needs network the first time] → Files are cached and verified under `build/`; a checksum mismatch fails the build with a clear message.
- [Candidate order changes, so smoke-test expectations tied to `luna_pinyin` order may shift] → Re-check `huiyi + 6` and `ceshi + 2` against real librime before running the smoke test.
- [Larger tables use more memory] → 28 MB table, memory-mapped by librime.
- [Learned words reset] → Accepted; noted in the implementation log.
