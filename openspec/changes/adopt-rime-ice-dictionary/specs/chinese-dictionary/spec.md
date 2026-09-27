## ADDED Requirements

### Requirement: Default Chinese Dictionary
The host SHALL use the `smartime_pinyin` schema by default, whose dictionary imports rime-ice's `8105`, `base`, `ext`, and `others` tables, and SHALL keep `luna_pinyin` available as a fallback schema.

#### Scenario: Current vocabulary
- **WHEN** the user types `yunyuansheng`, `neijuan`, or `fupan` in Chinese mode
- **THEN** the first candidate SHALL be 云原生, 内卷, or 复盘 respectively

#### Scenario: Everyday input still works
- **WHEN** the user types `nihao` and presses `Space`
- **THEN** 你好 SHALL be committed

### Requirement: Verified Dictionary Source
The build SHALL obtain the rime-ice tables from a pinned commit and SHALL verify each file's SHA-256 before using it. The tables SHALL NOT be committed to the repository.

#### Scenario: Checksum mismatch
- **WHEN** a downloaded table does not match its recorded SHA-256
- **THEN** the build SHALL fail with a message naming the file

#### Scenario: Cached files
- **WHEN** verified tables are already present under `build/rime-data/`
- **THEN** the build SHALL use them without downloading again

### Requirement: Precompiled Tables
Installing the host SHALL compile the Rime tables for the installing user before the host is next used.

#### Scenario: First keystroke after install
- **WHEN** the host is installed and the user types for the first time
- **THEN** the compiled `smartime_pinyin` tables SHALL already exist in the user's Rime build directory
