## 1. Candidate Panel

- [x] 1.1 Update `CandidateListView` metrics and fonts (design 1, 2) and the panel corner radius
- [x] 1.2 Draw the header hairline and include its spacing in the header height (design 3)
- [x] 1.3 Draw both chevrons on multi-page lists, dimming the unavailable one (design 4)
- [x] 1.4 Draw the panel border as a 0.5 pt hairline

## 2. Translation Popup

- [x] 2.1 Replace the `NSStackView` with explicit constraints and add `CapsuleBadgeView` for the direction (design 5)
- [x] 2.2 Add `TranslationPopupViewTests`: left and right insets for a long source line, and a message that wraps inside the insets

## 3. Review and Docs

- [ ] 3.1 Render before/after in light and dark; the user approves before install
- [ ] 3.2 Run `IMEHostCoreTests` locally through `swiftc` and in CI
- [x] 3.3 Update `docs/technical-design.md`, `docs/ime-manual-validation.md`, `docs/implementation-log.md`
- [ ] 3.4 Check the live panel and popup after installing the CI build
