## Why

`SmartIMEHost` is now a registered and selectable macOS input source, but it still fails to appear reliably in the menu bar input switcher and the keyboard input-source cycling flow. That blocks the current Chinese-input milestone because the IME cannot be reached through the normal runtime UX even after installation succeeds.

The current evidence points to two packaging and registration gaps:

- the bundle metadata is sufficient for `TISCreateInputSourceList` but not yet complete enough for stable UI display
- the logged-in user's `AppleEnabledInputSources` list can contain malformed `Keyboard Input Method` entries, which appears to poison switcher visibility

## What Changes

- Add explicit display metadata and localized display-name resources to `SmartIMEHost`
- Update the install workflow so it repairs malformed `AppleEnabledInputSources` data for the logged-in user and ensures `SmartIMEHost` is present as a valid enabled source
- Keep the current `TISTypeKeyboardInputMethodWithoutModes` registration model and avoid reintroducing mode-based registration
- Extend validation docs to cover switcher visibility, not just System Settings visibility

## Capabilities

### New Capabilities

- `ime-switcher-visibility`: A system-installed `SmartIMEHost` can appear in the menu bar input switcher and keyboard cycling flow after repository-owned installation steps

### Modified Capabilities

- `ime-install-validation`: Installation now repairs common local HIToolbox preference corruption that prevents a valid input source from appearing in the switcher

## Impact

- `Info.plist` and localized resource updates under `apps/ime/Resources`
- Install workflow changes in `scripts/ime/install-host.sh`
- Validation and implementation-log updates in `docs/`
