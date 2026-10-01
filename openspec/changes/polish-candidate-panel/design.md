## Context

`CandidateListView` draws the candidate panel by hand from a `Metrics` table; `TranslationPopupView` lays out three `NSTextField`s in an `NSStackView`. Both sit on an `NSVisualEffectView` (`.popover`) masked to rounded corners. Visual changes are reviewed through offscreen renders in light and dark, because the dev Mac cannot take screenshots.

## Decisions

### 1. Spacing follows one rule: concentric corners

Panel radius 12 minus outer padding 6 leaves the highlight a 6 pt radius, so the highlight's corners run parallel to the panel's. Row vertical padding goes 3 → 4 pt (row 26 → 28 pt); horizontal row padding stays 8 pt so short lists stay narrow (one-character list still under 80 pt wide).

### 2. Quieter row numbers

Numbers move to 12 pt medium `tertiaryLabelColor`. Medium keeps the smaller digits legible; tertiary lets the eye land on the candidate first. The highlighted row's number keeps the accent color.

### 3. Header gets a hairline, not a background

A 1 pt `separatorColor` line across the row width, 5 pt below the preedit (header height grows by that spacing). A filled header band was rejected: it competes with the highlight tint on row 1, which is highlighted most of the time.

### 4. Chevrons: both or none

On a multi-page list both chevrons are drawn in their fixed slots; the unavailable one uses `quaternaryLabelColor`. The model is unchanged (`canPageUp` / `canPageDown`); only drawing changes.

### 5. Popup layout with explicit constraints

`NSStackView` with `edgeInsets` reported a fitting width without the right inset (265 pt for a 253 pt line plus 12 pt left inset). Each line is now pinned to the leading edge, and the view's trailing edge is constrained `>=` each line's trailing edge plus the inset, so the fitting width is the widest line plus both insets. The direction badge is a small `CapsuleBadgeView` drawn like the 英/译 tags (11 pt medium, `quaternaryLabelColor` fill, `secondaryLabelColor` text).

## Risks

- Panels are 2 pt taller per row plus 9 pt for the header. A 9-row Chinese list near the bottom of the screen flips above the caret slightly sooner. Acceptable; placement logic is unchanged.
- Offscreen renders approximate the `.popover` material with a flat fill; the live panel blurs what is behind it. The user checks the live panel after install.
