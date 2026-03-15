## Why

`SmartIMEHost` can now build, install, register, and appear in the macOS input-source switcher, but the first real Chinese typing loop is still incomplete. Users cannot yet rely on the IME to show visible candidates and complete a normal pinyin-to-Chinese selection flow in a standard macOS text client.

## What Changes

- Add a repository-owned Chinese input loop that keeps inline composition and visible candidate presentation in sync for the active IME session
- Add explicit candidate-window management so the current `librime` candidate list is visible and selectable in normal macOS text clients
- Ensure Chinese candidate acceptance clears host and engine session state cleanly after commit or cancel
- Tighten manual validation so the milestone is only considered complete after `nihao`-style pinyin entry, candidate visibility, candidate acceptance, and cancel behavior all work in a real GUI client

## Capabilities

### New Capabilities
- `chinese-input-loop`: Complete the first end-to-end Chinese typing loop for `SmartIMEHost`, including inline composition, visible candidates, candidate selection, commit, and cancel behavior

### Modified Capabilities

## Impact

- `apps/ime/Sources/IMEHostCore`
- `packages/rime-bridge`
- `packages/shared-models`
- `docs/ime-manual-validation.md`
- `docs/implementation-log.md`
