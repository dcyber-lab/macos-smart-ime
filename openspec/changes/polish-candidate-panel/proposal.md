## Why

The user asked for a nicer-looking UI. The candidate panel works but looks cramped and plain: 4 pt outer padding, 26 pt rows, 16 pt candidates, a pale highlight, and a preedit header that runs straight into the first row. The page chevrons appear and disappear while paging. The selection translation popup's source line touches its right edge, because `NSStackView` drops the trailing inset when it computes the fitting width.

A first pass that only adjusted spacing looked unchanged to the user. Four live on-screen variants were then compared (current, solid highlight, solid highlight on Liquid Glass, horizontal on glass), and the user picked **vertical with a solid highlight on the existing `.popover` material**.

## What Changes

- Highlight: the selected row gets a solid accent-color fill with white text, number, gloss, and tag. This replaces the soft accent tint.
- Candidate text: 16 → 17 pt.
- Spacing: corner radius 10 → 12 → 14 pt, outer padding 4 → 6 pt, row height 26 → 31 pt, row side padding 8 → 9 pt. The highlight radius is 8 pt, concentric with the panel corner.
- Row numbers: 13 pt regular secondary → 12 pt medium tertiary.
- Preedit header: 12 pt → 13 pt medium, with a hairline under it.
- Page indicator: on multi-page lists both chevrons are shown and the unavailable direction is dimmed, so the control no longer changes shape while paging.
- Panel border: 1 pt → 0.5 pt hairline.
- Translation popup: the direction (英 → 中) becomes a capsule badge like the 英/译 tags, followed by the source text. Explicit constraints replace `NSStackView`, which fixes the clipped source line. Insets 10/12 → 11/14 pt. The popup shares the panel's 14 pt corner radius.
- Unchanged: the `.popover` visual-effect material, vertical layout, panel placement, and all keyboard and click behavior.

## Non-goals

- Liquid Glass (`NSGlassEffectView`) and a horizontal layout. Both were previewed live, and the user did not pick them.
- Themes, font settings, or a user-selectable layout.

## Capabilities

### New Capabilities
- (None)

### Modified Capabilities
- `candidate-panel`: solid accent highlight; both page chevrons shown, with the unavailable one dimmed; header separated from the rows.
- `selection-translation`: the popup shows the direction as a badge and keeps its insets on both sides.

## Impact

- `apps/ime/Sources/IMEHostCore/CandidatePanel.swift`, `TranslationPopup.swift`.
- `apps/ime/Tests/IMEHostCoreTests`: new `TranslationPopupViewTests` (left and right insets, message wrapping); existing `CandidateListViewTests` unchanged.
- Panels grow: a 9-row Chinese list goes from 107×268 to 113×334 pt, and a 5-row English list from 192×133 to 202×167 pt.
- `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`.
