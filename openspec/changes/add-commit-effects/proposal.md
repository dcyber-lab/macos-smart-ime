## Why

The user wants committing a candidate to feel lively: the selected row should shatter into colored fragments. After seeing three motions and four palettes as live on-screen prototypes, the user asked for all of them as switchable skins, applied in both Chinese and English mode, with a random option.

## What Changes

- Committing a candidate from the panel plays a short effect on that row while the rest of the panel fades out in 100 ms. The committed text is inserted first; the effect is purely visual and never delays input.
- Three motions:
  - 玻璃炸裂: cracks flash, then triangular shards burst outward and fall.
  - 碎裂下坠: the row breaks left to right and drops.
  - 粒子消散: the row dissolves into fine particles drifting up and right.
- Four palettes:
  - 彩虹, 霓虹, 马卡龙: shards take random colors (glass) or a left-to-right gradient (crumble, dust); text fragments stay white.
  - 跟随强调色: shards keep the row's own accent color.
- A 随机 option for each axis picks a new motion or palette on every commit.
- Switching: two submenus in the input menu (menu bar), 选词动效 and 碎片配色, with a check mark on the current choice. Choosing an item plays a preview next to the pointer. The settings are stored in the input method's defaults (`CommitEffect`, `CommitEffectPalette`), so `defaults write` works too.
- Defaults: 玻璃炸裂 with 彩虹. With Reduce Motion on, no effect plays.
- Triggers: any commit whose text matches a panel row — `Space`, number keys, clicks, punctuation that commits the first candidate, and in English mode also `Return` (the typed text is row 1). `Escape` and raw-pinyin commits play nothing.

## Capabilities

### New Capabilities
- `commit-effects`: the commit animation, its skins, how they are switched, and the guarantee that input is never delayed.

### Modified Capabilities
- `candidate-panel`: on commit, the panel fades out in 100 ms with the committed row removed, instead of disappearing at once.

## Impact

- New in `IMEHostCore`:
  - `CommitEffect.swift`: pure geometry and timing, deterministic per seed.
  - `CommitEffectView.swift`: drawing, overlay windows, and the display link.
  - `CommitEffectSettings.swift`.
- `CandidatePanel.swift`: row snapshots, the committed-row lookup, and the fade on commit.
- `IMEInputController.swift`: plays the effect after a commit; adds the input menu.
- `IMEHostCoreTests`: effect model, settings, and committed-row tests.
- `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`.
