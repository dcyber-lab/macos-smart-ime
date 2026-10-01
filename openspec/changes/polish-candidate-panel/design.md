## Context

`CandidateListView` draws the candidate panel by hand from a `Metrics` table. `TranslationPopupView` lays out three `NSTextField`s in an `NSStackView`. Both sit on an `NSVisualEffectView` (`.popover`) masked to rounded corners. Offscreen renders cannot show the material's blur or Liquid Glass, and the dev Mac cannot take screenshots. Style variants were therefore shown to the user as real on-screen panels from a scratch preview app, and the chosen one was then checked in offscreen renders, light and dark.

## Decisions

### 1. Solid accent highlight

The highlighted row is filled with `controlAccentColor`. Its text is white, and its number, gloss, and tag text are white at 80%; the tag capsule is white at 25%. Each row draws one fixed color set, so the dark-mode text lightening the tint needed is gone. White on the default blue accent is about 4:1, which is enough for 17 pt text. The user picked this over the tint after seeing both live.

### 2. Spacing follows concentric corners

Panel radius 14 minus outer padding 6 leaves the highlight an 8 pt radius, so the highlight corners run parallel to the panel's. With 17 pt text and 5 pt vertical padding, rows are 31 pt. Side padding is 9 pt, and a one-character list stays under 80 pt wide.

### 3. Quieter row numbers

Numbers are 12 pt medium in `tertiaryLabelColor`, so the eye lands on the candidate first. Medium weight keeps the smaller digits legible.

### 4. Header hairline, not a background

A 1 pt `separatorColor` line sits 5 pt below the preedit and is inset like the group separators. The header height grows by that spacing. A filled header band was rejected: it would compete with the highlight on row 1, which is highlighted most of the time.

### 5. Chevrons: both or none

On a multi-page list, both chevrons are drawn in their fixed slots, and the unavailable one uses `quaternaryLabelColor`. The model (`canPageUp` / `canPageDown`) is unchanged; only drawing changes.

### 6. Popup layout with explicit constraints

With `edgeInsets`, `NSStackView` reported a fitting width without the right inset: 265 pt for a 253 pt line plus a 12 pt left inset. Each line is now pinned to the leading edge, and the view's trailing edge is constrained `>=` each line's trailing edge plus the inset, so the fitting width is the widest line plus both insets. The direction badge is a small `CapsuleBadgeView`, drawn like the 英/译 tags.

## Risks

- Panels are taller: 31 pt rows instead of 26 pt, plus 9 pt for the header. A 9-row Chinese list near the bottom of the screen flips above the caret sooner. The placement logic is unchanged.
- With a light accent color (yellow, graphite), white text has less contrast. macOS uses the same white-on-accent pairing for list selection, so this matches the system.
