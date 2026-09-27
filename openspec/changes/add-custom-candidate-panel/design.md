## Context

`IMEInputController.syncCandidateWindow()` pushes candidate strings into an `IMKCandidates` panel (`kIMKSingleColumnScrollingCandidatePanel`) and mirrors the highlighted index into it. The stock panel only accepts plain strings, offers almost no styling, and calls back through `candidateSelected` / `candidateSelectionChanged`, which needed an `isSyncingCandidateSelection` guard to avoid recursion. Candidates now carry a `CandidateSource` (`.rime`, `.englishCompletion`, `.englishTranslation`), and Chinese mode mixes those sources in one list, but the panel cannot show the difference.

The chosen look (confirmed with the user) is a vertical list:

```
╭────────────────────╮
│ 1  数据库          │
│ 2  数据            │
│ ...                │
│ ────────────────── │
│ 6  database     译 │
╰────────────────────╯
```

## Goals / Non-Goals

**Goals:**
- A good-looking vertical panel that follows system light/dark appearance.
- Make English words and translations visually distinct only when they are mixed with Chinese candidates.
- Keep keyboard interaction identical, and add click-to-select.
- Keep layout and placement logic unit-testable without showing windows.

**Non-Goals:**
- Horizontal layout, user themes, or font-size settings (future Companion settings).
- Animations.
- VoiceOver support for the panel (follow-up; the stock panel's accessibility is lost in this change).

## Decisions

### 1. Custom `NSPanel` instead of styling `IMKCandidates`
`IMKCandidates` only exposes panel types and a few attributes; it cannot draw per-row tags or group separators. A borderless, non-activating `NSPanel` drawn with AppKit gives full control and is what Squirrel does.

Alternatives considered:
- *Tune `IMKCandidates`* (horizontal panel type, fonts): still looks stock and cannot distinguish sources.
- *SwiftUI in `NSHostingView`*: more code weight and sizing quirks in a background IME process for a panel that is a handful of text rows; plain AppKit drawing is lighter and predictable.

### 2. Pure model and placement, thin AppKit view
- `CandidatePanelModel` turns `CompositionState` into rows: label (`1`…`9`), text, optional tag, highlighted flag, and whether a separator precedes the row.
- `CandidatePanelPlacement` computes the panel frame from the panel size, caret rectangle, and the screen's visible frame.
- `CandidatePanel` (window plus a custom `NSView`) only measures and draws rows.

The model and placement are covered by a new `IMEHostCoreTests` target.

### 3. Grouping and tags
- Chinese group: `.rime`, `.placeholder`. English group: `.englishCompletion`, `.englishCorrection`, `.englishTranslation`.
- Tags and separators appear only when both groups are present. Tag text: 译 for `.englishTranslation`, 英 for other English sources.
- A separator is drawn wherever the group changes between consecutive rows, so an English word placed first (`hello`) is separated from the Chinese rows below it.

### 4. Look
- Background: `NSVisualEffectView` (`.popover` material, `.active` state) with a 10 pt corner radius and the window shadow. It adapts to light/dark automatically.
- Rows: candidate text in the 16 pt system font with `labelColor`; index in 13 pt monospaced-digit `secondaryLabelColor`; tag in 11 pt `tertiaryLabelColor`, right-aligned.
- Highlighted row: rounded rectangle filled with `controlAccentColor` at low opacity (a soft tint); the candidate text and index use `controlAccentColor`. A solid accent fill with white text looked heavy in a small panel.
- Tags: capsule with a `quaternaryLabelColor` fill and `secondaryLabelColor` 10 pt medium text; on the highlighted row the capsule uses the accent tint.
- Header (Chinese mode only): the Rime preedit in 12 pt `secondaryLabelColor` above the rows, with `chevron.up` / `chevron.down` symbols at its right edge when earlier or later pages exist (`candidatePageIndex > 0`, `!isLastCandidatePage`). Hidden in English mode, where the first row already shows the typed text.
- Separator: 1 pt `separatorColor` line inset to the row padding.

### 5. Window behavior and placement
- One shared panel instance for the process (IMK creates one controller per client, but only one composition is active). Each `show` call replaces the click handler with the calling controller's.
- Borderless, `.nonactivatingPanel`, never key or main, window level just below the cursor level (as Squirrel), `collectionBehavior` includes `.canJoinAllSpaces` and `.fullScreenAuxiliary`.
- Caret rectangle comes from `client().attributes(forCharacterIndex: 0, lineHeightRectangle:)`. If the client returns an empty rectangle, reuse the last known position; if there is none, use the mouse location.
- The panel's top-left sits 4 pt below the caret's bottom-left. If that would cross the bottom of the visible frame, the panel moves above the caret instead. The x position is clamped so the panel stays within the visible frame.

### 6. Controller changes
`syncCandidateWindow()` shows the panel with the current `CompositionState` when there is composition text and at least one candidate, and hides it otherwise. `commitComposition`, `deactivateServer`, and `inputControllerWillClose` hide it. A row click calls the active engine's `selectCandidate(at:)` through the existing `apply(_:sender:)`. `candidateSelected`, `candidateSelectionChanged`, `isSyncingCandidateSelection`, and the `IMKCandidates` selection-key setup are removed.

## Risks / Trade-offs

- [Some clients (Terminal, Electron apps) report an empty caret rectangle] → Fall back to the last known position, then the mouse location.
- [Panel left visible after focus moves] → Hide on every path that ends the composition, including deactivation and controller close.
- [Loss of the stock panel's VoiceOver support] → Documented non-goal; a follow-up can add `NSAccessibility` rows.
- [Redraw cost per keystroke] → At most nine short strings are measured and drawn; negligible compared to Rime processing.

## Migration Plan

No data migration. Rollback is restoring the `IMKCandidates` code path in `IMEInputController`.

## Open Questions

- Should candidate font size and panel layout (vertical/horizontal) become Companion settings?
