## Why

Phase 1 of the project requires an English input mode that supports normal typing, completion, and basic correction. Currently, the IME is hardcoded to Chinese input via `librime`, which limits its usability for knowledge workers who frequently switch between languages.

## What Changes

- Add a new `EnglishInputEngine` protocol and a basic implementation in `packages/english-engine`.
- Update `IMEInputController` to support toggling between Chinese and English modes (e.g., via a dedicated key or shortcut).
- Integrate the English engine into the IME host real-time path.
- Enable basic English word completion and candidate presentation in the IME UI.

## Capabilities

### New Capabilities
- `english-input-mode`: Support for basic English typing with mode toggling.
- `english-completion`: Word-level English completion candidates based on current input.

### Modified Capabilities
- (None)

## Impact

- `apps/ime/Sources/IMEHostCore/IMEInputController.swift`: Mode switching logic and engine routing.
- `packages/english-engine`: New package implementation for English logic.
- `packages/shared-models`: Refinement of `CompositionState` and `InputMode` usage.
- `apps/ime/Sources/IMEHostCore/IMEHostSessionStore.swift`: Session state updates for English mode.
