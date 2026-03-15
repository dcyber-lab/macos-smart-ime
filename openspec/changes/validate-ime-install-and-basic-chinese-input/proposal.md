## Why

The repository can now build a real macOS IME host and route Chinese composition through `librime`, but the project still lacks a repeatable installation and hand-validation workflow. Without that workflow, the team cannot reliably confirm that the input method appears in macOS input sources, can be enabled, and performs a basic Chinese input loop in a real client application.

## What Changes

- Add a repeatable local install workflow for `SmartIMEHost`
- Add repository-owned scripts for building and installing the IME app into `/Library/Input Methods/`
- Add a clear manual validation checklist for enabling the input method and verifying basic Chinese input behavior
- Update local documentation so future agents and developers follow one install-and-validate path

## Capabilities

### New Capabilities

- `ime-install-validation`: Build, install, and manually validate the current IME host as a system input method on macOS

### Modified Capabilities

- `ime-host-shell`: Extend the existing host milestone with documented installation and validation steps instead of build-only verification

## Impact

- New scripts under a repository-owned install/validation path
- Documentation updates in `apps/ime` and `docs/`
- Possible small project setting adjustments if they are required for repeatable local installation
