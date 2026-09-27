## 1. Dictionary Data

- [x] 1.1 Add `scripts/rime/fetch-rime-ice.sh` with the pinned commit and SHA-256 checksums for `8105`, `base`, `ext`, `others`, and `LICENSE`
- [x] 1.2 Add `third_party/librime-data/smartime/` with `smartime_pinyin.schema.yaml`, `smartime_pinyin.dict.yaml`, and a `default.yaml` listing `smartime_pinyin` then `luna_pinyin`
- [x] 1.3 Add `scripts/rime/assemble-shared-data.sh` producing `build/rime-data/shared/`, and run fetch + assemble from `scripts/ime/build-host.sh`

## 2. Host

- [x] 2.1 Point `RIME_SHARED_DATA_DIR` at `$(SRCROOT)/build/rime-data/shared` in `project.yml` and regenerate the Xcode project
- [x] 2.2 Set `IMEHostConfiguration.defaultSchemaID` to `smartime_pinyin`
- [x] 2.3 Run `rime_deployer --build` for the target user in `scripts/ime/install-host.sh` after stopping the host

## 3. Verification and Docs

- [x] 3.1 Verify checksum failure and cached-file behavior of the fetch script
- [x] 3.2 Probe real librime with the assembled data (云原生, 内卷, 复盘, 你好) and re-check smoke-test candidate positions
- [x] 3.3 Run `scripts/ime/dev-cycle.sh`; confirm compiled tables exist before the first keystroke
- [x] 3.4 Update `docs/implementation-log.md`, `docs/technical-design.md`, `docs/ime-manual-validation.md`, and add third-party notices for rime-ice (GPL-3.0)
