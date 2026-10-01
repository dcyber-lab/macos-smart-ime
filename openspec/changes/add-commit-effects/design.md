## Context

The candidate panel (`CandidatePanel`, `CandidateListView`) is redrawn on every key and hidden when the composition ends. Commits happen in `IMEInputController.apply(_:sender:)`: the text is inserted, the session resets, and `syncPresentation()` hides the panel. Every input controller call runs on the main thread, so any per-frame work there competes with key handling.

A scratch prototype (live windows plus offscreen frame strips) settled the motions, timings, and palettes with the user.

## Decisions

### 1. Insert first, animate after, in separate windows

The effect starts after `insertText` and works from a snapshot of the row. The panel's own window is free right away for the next composition. Fragments are drawn in borderless, click-through overlay windows one level above the panel, so they fly over a new panel rather than under it. A pool of three overlays allows overlapping commits; when all are busy, the oldest effect is cut short and its overlay reused. Each overlay covers the row plus the flight area (200 pt either side, 140 pt above, 260 pt below).

### 2. Pure model, thin renderer

`CommitEffect` computes every fragment from the row size, motion, palette, and a seed:
- polygon, initial velocity, spin, delay, lifetime, and end scale;
- `pose(of:at:)` returns offset, rotation, scale, and alpha at a given time, or nil once the fragment is gone.

It has no AppKit drawing and is unit-tested. `CommitEffectView` draws poses each frame from a display link (macOS 14+, with a 120 Hz timer as fallback). When an effect starts, each shard is pre-rendered once into a small bitmap (clip, palette fill, sheen, text, edge), so a frame only draws bitmaps with a transform and alpha, and dust only fills rectangles. Clipping and redrawing the whole row image for every shard on every frame measured 5 ms per frame on average and 33 ms at worst for a 190 pt row; pre-rendering brings that to 1.1 ms and 2.9 ms. Building the effect runs on the next main-actor turn, so key handling only pays for the snapshot (about 2 ms in total).

| Motion | Fragments | Physics | Length |
|---|---|---|---|
| 玻璃炸裂 | jittered 3-row grid of triangles, about 16 pt columns | 60 ms white crack lines, then a radial burst from the row center (160–320 pt/s, faster near the center), upward bias, gravity 1100 pt/s², spin up to 10 rad/s, shrink to 50% | ~0.6 s |
| 碎裂下坠 | 2-row triangle grid, 15 pt columns | delay grows left to right (160 ms across), small drift, gravity 1500 pt/s² | ~0.75 s |
| 粒子消散 | 3 pt squares colored from the snapshot | left-to-right sweep (200 ms), drift up-right, slight lift, shrink to 20% | ~0.8 s |

### 3. Colored fragments keep the text

Two snapshots of the committed row are taken: as drawn (accent fill, white text) and text only (`CandidateListView.drawsHighlightFill = false`). A tinted shard is filled with its palette color plus a white sheen toward the top, then the text snapshot is drawn clipped to it. Each shard crossfades from the original snapshot to its color over the first 80 ms of flight. Dust cells that are text stay white; the others take the gradient color. Pieces that have not started moving are drawn from the snapshot in one clipped pass, so a dissolving row stays sharp. Glass shards get random palette colors (confetti); crumble and dust use a left-to-right gradient.

### 4. Finding the committed row

`CandidatePanelModel.committedRowIndex(rows:committedText:)`:
1. An exact text match, preferring the highlighted row.
2. Otherwise the longest row text that the committed text starts with. This covers English `Space` ("deploy ") and punctuation ("你好，").
3. Otherwise nil, and no effect plays (`Return` with raw pinyin).

The longest-prefix rule keeps 你 from matching a commit of 你好. The panel re-renders the matched row as highlighted for the snapshot, so a number-key pick of an unhighlighted row still shatters in color.

### 5. Panel fade without races

`playCommitEffect(for:)` sets a pending fade; the following `hide()` vacates the row and animates the window alpha to 0 over 100 ms. `show()` clears the pending fade, cancels any running fade with a zero-duration alpha animation to 1, and bumps a generation counter. The fade's completion handler orders the window out only if the generation is unchanged, so typing right after a commit never leaves the new panel invisible.

### 6. Settings and menu

`CommitEffectSettings` reads `CommitEffect` (`shatter`, `crumble`, `dust`, `random`, `off`) and `CommitEffectPalette` (`rainbow`, `neon`, `pastel`, `accent`, `random`) on every commit, like the other settings. Unknown values fall back to the defaults. `random` resolves per commit. `NSWorkspace.accessibilityDisplayShouldReduceMotion` turns effects off.

`IMEInputController.menu()` lists both settings flat (`CommitEffectMenu`): a disabled section title, then the choices, indented, with the current one checked. The first build used submenus. The system displayed them, but choosing an item never reached the controller (nothing was saved), so the menu is flat, as in Squirrel and McBopomofo. Each item's tag identifies its choice, with the title as a fallback. IMK delivers the choice through `doCommand(by:command:)`, which logs the selector, with an info dictionary whose `kIMKCommandMenuItemName` entry is the chosen `NSMenuItem`. The action writes the setting and plays a preview on a sample row ("灵译输入法") below the pointer.

## Risks

- Main-thread cost: measured with the real `IMEHostCore` in an optimized build. In key handling it is about 2 ms per commit. Per frame it is under 1.1 ms on average and under 3 ms at p99, even for a long English row, so a key typed during an effect waits at most one such frame.
- Input menu actions can only be verified live; submenu actions did not arrive, which is why the menu is flat.
- Fragments over a new panel are briefly visible while typing fast; they fade within about 0.6 s.
