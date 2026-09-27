## 1. Model and Placement

- [x] 1.1 Add `CandidatePanelModel` in `IMEHostCore` that builds rows (label, text, tag, highlighted, separator-before) from `CompositionState`, with the grouping and tag rules
- [x] 1.2 Add `CandidatePanelPlacement` that computes the panel frame from panel size, caret rectangle, and visible screen frame (below, flip above, clamp horizontally)
- [x] 1.3 Add the `IMEHostCoreTests` target and tests for every grouping, highlight, and placement scenario in `specs/candidate-panel/spec.md`

## 2. Panel Window and Drawing

- [x] 2.1 Add `CandidatePanel`: shared borderless non-activating `NSPanel` with an `NSVisualEffectView` background, rounded corners, shadow, and cursor-adjacent window level
- [x] 2.2 Draw rows (index, text, tag, separators, accent-color highlight) and size the panel to its content
- [x] 2.3 Route row clicks to a click handler supplied by the controller
- [x] 2.4 Render the panel offscreen in light and dark appearances and check the images

## 3. Controller Integration

- [ ] 3.1 Replace `IMKCandidates` in `IMEInputController.syncCandidateWindow()` with `CandidatePanel`, passing the caret rectangle from `client().attributes(forCharacterIndex:lineHeightRectangle:)`
- [ ] 3.2 Hide the panel on commit, `Escape`, deactivation, and controller close; select candidates on row click through `apply(_:sender:)`
- [ ] 3.3 Remove `candidateSelected`, `candidateSelectionChanged`, `isSyncingCandidateSelection`, and the stock selection-key setup
- [ ] 3.4 Confirm `swift test` passes and `scripts/ime/build-host.sh` builds the host

## 4. Validation and Docs

- [ ] 4.1 Add a "Candidate Panel" checklist to `docs/ime-manual-validation.md` (light/dark, tags and separators, highlight, placement near screen edges, click selection, hiding)
- [ ] 4.2 Run the checklist in a real macOS text client
- [ ] 4.3 Update `docs/implementation-log.md` and `docs/technical-design.md`

## Status Note

The panel (`CandidatePanel`, `CandidatePanelModel`) and its model/placement tests exist, but controller wiring was reverted on 2026-09-27 while diagnosing a text-commit bug that turned out to be unrelated (see `docs/implementation-log.md`). The user also judged the rendered panel unattractive; revisit the visual design with the user before re-wiring, and verify in a real client before hand-off.
