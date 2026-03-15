## Why

The project needs a working macOS IME host before any Chinese input, English completion, or Companion features can be implemented safely. This change establishes the minimum InputMethodKit-based shell so the team can validate lifecycle, activation, composition, and commit behavior early.

## What Changes

- Create the first runnable macOS IME host application under `apps/ime`
- Add the minimum InputMethodKit wiring needed to receive input events and commit text
- Introduce a small shared session model for composition and candidate state
- Provide a stub candidate/update flow that proves the end-to-end host path works without depending on `librime` yet
- Define the boundary between the IME host layer and future input engines

## Capabilities

### New Capabilities
- `ime-host-shell`: Bootstrap a macOS IME host that can be enabled, receive input events, manage a minimal input session, and commit test text

### Modified Capabilities

## Impact

- New code in `apps/ime`
- New shared types in `packages/shared-models`
- Future `rime-bridge` and `english-engine` work will build on this host boundary
- Requires Xcode/macOS app target setup for InputMethodKit validation
