## Why

The IME host shell is now buildable, but it still uses placeholder session logic. The next milestone is to replace that stub path with a real `librime` bridge so the project can validate Chinese input, candidate generation, and commit behavior through the production input core chosen in the technical design.

## What Changes

- Add the first `packages/rime-bridge` package with a narrow Swift-facing wrapper around `librime`
- Introduce a host-to-engine boundary so the IME host delegates Chinese composition work to the bridge instead of placeholder logic
- Map `librime` session state into the shared composition and candidate models already used by the host
- Document the local runtime assumptions required to run the bridge during development

## Capabilities

### New Capabilities

- `rime-bridge`: Provide a project-owned bridge that initializes `librime`, manages sessions, processes key events, and returns composition/candidate/commit updates to the IME host

### Modified Capabilities

- `ime-host-shell`: Replace placeholder Chinese composition behavior with bridge-backed updates while preserving the existing InputMethodKit host boundary

## Impact

- New code in `packages/rime-bridge`
- Host integration changes in `apps/ime/Sources/IMEHostCore`
- Shared model adjustments if the current session types need small bridge-facing extensions
- Local developer setup will need a documented `librime` installation or build path for validation
