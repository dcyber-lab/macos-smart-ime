## 1. Model and Placement

- [x] 1.1 Add `CandidatePanelModel` in `IMEHostCore` that builds rows (label, text, tag, highlighted, separator-before) from `CompositionState`, with the grouping and tag rules
- [x] 1.2 Add `CandidatePanelPlacement` that computes the panel frame from panel size, caret rectangle, and visible screen frame (below, flip above, clamp horizontally)
- [x] 1.3 Add the `IMEHostCoreTests` target and tests for every grouping, highlight, and placement scenario in `specs/candidate-panel/spec.md`

## 2. Panel Window and Drawing

- [x] 2.1 Add `CandidatePanel`: shared borderless non-activating `NSPanel` with an `NSVisualEffectView` background, rounded corners, shadow, and cursor-adjacent window level
- [x] 2.2 Draw rows (index, text, tag, separators, accent-color highlight) and size the panel to its content
- [x] 2.3 Route row clicks to a click handler supplied by the controller
- [x] 2.4 Render the panel offscreen in light and dark appearances and check the images
- [x] 2.5 Add a test that the panel height fits the row count (no empty rows) and shrinks when rows are removed

## 3. Controller Integration

- [x] 3.1 Replace `IMKCandidates` in `IMEInputController.syncCandidateWindow()` with `CandidatePanel`, passing the caret rectangle from `client().attributes(forCharacterIndex:lineHeightRectangle:)`
- [x] 3.2 Hide the panel on commit, `Escape`, deactivation, and controller close; select candidates on row click through `apply(_:sender:)`
- [x] 3.3 Remove `candidateSelected`, `candidateSelectionChanged`, `isSyncingCandidateSelection`, and the stock selection-key setup
- [x] 3.4 Confirm `swift test` passes and `scripts/ime/build-host.sh` builds the host

## 4. Validation and Docs

- [x] 4.1 Add a "Candidate Panel" checklist to `docs/ime-manual-validation.md` (light/dark, tags and separators, highlight, placement near screen edges, click selection, hiding)
- [ ] 4.2 Run the checklist in a real macOS text client, including committing with `Space`, number keys, `Return`, and a row click, and capture a screenshot of the live panel
- [x] 4.3 Update `docs/implementation-log.md` and `docs/technical-design.md`

## 5. Visual Refinements

- [x] 5.1 Add `isLastCandidatePage` to `CompositionState` and fill it from `RimeMenu.is_last_page`
- [x] 5.2 Extend the panel model with a header (preedit in Chinese mode) and page indicator, with tests for every header and page scenario
- [x] 5.3 Draw the soft accent-tint highlight, capsule tags, and the header with chevrons; include the header in panel sizing
- [x] 5.4 Render before/after previews in light and dark for user review
- [x] 5.5 Deploy with `scripts/ime/dev-cycle.sh` after the user approves the previews

## Status Note

Wiring was reverted on 2026-09-27 while diagnosing an unrelated text-commit bug, then restored after that bug was fixed. The smoke test (first `scripts/ime/e2e-textedit.swift`, now `scripts/ime/e2e/`) verified committing with `Space`, number keys, `Return`, `Escape`, and a row click in TextEdit, plus live panel heights. Task 4.2 stays open for the user's visual review of the live panel (automated screenshots need screen-capture permission).
