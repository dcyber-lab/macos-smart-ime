## Why

The candidate panel and the selection translation popup work but look cramped: 4 pt outer padding, 26 pt rows, and a Chinese-mode preedit header that runs straight into the first row. The page chevrons appear and disappear while paging, and the popup's source line touches its right edge because `NSStackView` drops the trailing inset when computing the fitting width.

## What Changes

- Candidate panel spacing: corner radius 10 → 12 pt, outer padding 4 → 6 pt, row height 26 → 28 pt, label-to-text gap 7 → 8 pt. The highlight keeps a 6 pt radius, concentric with the panel corner.
- Row numbers: 13 pt regular secondary → 12 pt medium tertiary, so the candidates stand out. The highlighted row keeps its accent-colored number.
- Preedit header: 12 pt → 13 pt medium, with a hairline under it separating it from the rows.
- Page indicator: when the list has more than one page, both chevrons are shown and the unavailable direction is dimmed, so the control does not move or change shape while paging.
- Panel border: 1 pt → 0.5 pt hairline.
- Translation popup: the direction (英 → 中) becomes a capsule badge styled like the 英/译 tags, followed by the source text. Explicit constraints replace `NSStackView`, so the fitting width keeps the right inset (fixes the clipped source line). Insets 10/12 → 11/14 pt.
- Unchanged: the soft accent-tint highlight the user chose on 2026-09-27, the `.popover` visual-effect material, panel placement, and all keyboard and click behavior.

## Non-goals

- Liquid Glass (`NSGlassEffectView`): it renders only on screen, and automated screenshots are not permitted on the dev Mac, so it cannot be reviewed offscreen like these changes. It can be a follow-up with a live review.
- Themes, font settings, or horizontal layouts.

## Capabilities

### New Capabilities
- (None)

### Modified Capabilities
- `candidate-panel`: page indicator shows both chevrons with the unavailable one dimmed; header is separated from the rows.
- `selection-translation`: the popup shows the direction as a badge and keeps its insets on every side.

## Impact

- `apps/ime/Sources/IMEHostCore/CandidatePanel.swift`, `TranslationPopup.swift`.
- `apps/ime/Tests/IMEHostCoreTests`: new `TranslationPopupViewTests` (left and right insets, message wrapping); existing `CandidateListViewTests` unchanged.
- Panels grow slightly: a 9-row Chinese list goes from 107×268 to 111×298 pt.
- `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`.
