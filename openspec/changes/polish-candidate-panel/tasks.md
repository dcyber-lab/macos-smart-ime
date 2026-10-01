## 1. Candidate Panel

- [x] 1.1 Draw the solid accent highlight with white text, number, gloss, and tag (design 1)
- [x] 1.2 Update `CandidateListView` metrics and fonts and the panel corner radius (design 2, 3)
- [x] 1.3 Draw the header hairline and include its spacing in the header height (design 4)
- [x] 1.4 Draw both chevrons on multi-page lists, dimming the unavailable one (design 5)
- [x] 1.5 Draw the panel border as a 0.5 pt hairline

## 2. Translation Popup

- [x] 2.1 Replace the `NSStackView` with explicit constraints and add `CapsuleBadgeView` for the direction (design 6)
- [x] 2.2 Add `TranslationPopupViewTests`: left and right insets for a long source line, and a message that wraps inside the insets

## 3. Review and Docs

- [x] 3.1 Show style variants live on screen; the user picked vertical with a solid highlight (2026-10-01); check the implementation in light and dark renders
- [x] 3.2 Run `IMEHostCoreTests` locally through `swiftc` (75 pass) and in CI (176 pass)
- [x] 3.3 Update `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`
- [x] 3.4 Check the live panel and popup after installing the CI build
