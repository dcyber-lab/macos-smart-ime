## 1. Effect Model

- [x] 1.1 `CommitEffect.swift`: motions, palettes, seeded generator, fragment generation and `pose(of:at:)` (design 2, 3)
- [x] 1.2 Tests: deterministic per seed, shards tile the row, fragments start at rest, all gone after `duration`, durations under 1 s, palettes tint shards, text dust stays white

## 2. Rendering and Panel

- [x] 2.1 `CommitEffectView.swift`: drawing, display link with timer fallback, overlay window pool (design 1, 3)
- [x] 2.2 `CandidateListView.drawsHighlightFill`, row snapshots, `CandidatePanelModel.committedRowIndex` with tests (design 4)
- [x] 2.3 `CandidatePanel.playCommitEffect(for:)` and the race-free fade (design 5)

## 3. Settings, Controller, Menu

- [x] 3.1 `CommitEffectSettings` with tests (defaults, unknown values, random, Reduce Motion)
- [x] 3.2 Play the effect from `IMEInputController.apply` after inserting the text
- [x] 3.3 Input menu with check marks and a preview on selection (design 6); flat sections after submenu actions did not arrive

## 4. Verification and Docs

- [ ] 4.1 Run `IMEHostCoreTests` locally through `swiftc` (103 pass) and in CI
- [x] 4.2 Update `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`
- [ ] 4.3 Install the CI build; the user checks every skin, the menu, fast typing, and Reduce Motion
