## Why

The host shows candidates with the stock `IMKCandidates` single-column scrolling panel. It has a fixed height, so short lists leave a block of empty rows below the candidates; it cannot be styled, looks out of place next to other input methods (Squirrel draws its own panel), and gives no way to tell English words and translations apart from Chinese candidates now that Chinese mode mixes them. Users judged it ugly after trying English candidates in Chinese mode.

## What Changes

- Replace `IMKCandidates` with a project-drawn vertical candidate panel owned by `IMEHostCore`.
- Size the panel to its content: the height fits exactly the current rows and the width fits the longest row, recomputed on every update.
- Visual design: rounded corners, translucent background that follows the system light/dark appearance, one numbered row per candidate, the highlighted row drawn with a soft accent-color tint and accent-colored text.
- In Chinese mode, show the pinyin being typed (the Rime preedit) in small secondary text above the candidates, and show up/down chevrons next to it when more candidate pages exist.
- When a list mixes Chinese and English candidates, draw a separator between the Chinese and English groups and a small capsule tag on English rows: 英 for English words, 译 for translations. Lists with a single kind (e.g. English mode) show no tags or separators.
- Position the panel just below the caret, flip it above the caret when there is not enough room below, and keep it inside the visible screen area.
- Clicking a row selects that candidate. Keyboard behavior (number keys, arrow highlight, `Space`, `Return`, `Escape`) is unchanged.
- Remove the `IMKCandidates` delegate plumbing (`candidateSelected`, `candidateSelectionChanged`, and the selection-sync recursion guard) that only existed for the stock panel.

## Capabilities

### New Capabilities
- `candidate-panel`: Appearance, grouping, tagging, highlight, placement, and mouse selection of the host-drawn candidate panel.

### Modified Capabilities
- (None)

## Impact

- `apps/ime/Sources/IMEHostCore/`: new `CandidatePanel` (window and drawing) and a pure `CandidatePanelModel` that turns `CompositionState` into rows; `IMEInputController` drives the new panel and drops `IMKCandidates`.
- `Package.swift`: new `IMEHostCoreTests` test target for the row model and placement math.
- `packages/shared-models`: `CompositionState` gains `isLastCandidatePage`; `packages/rime-bridge` fills it from `RimeMenu.is_last_page`.
- No changes to key routing.
