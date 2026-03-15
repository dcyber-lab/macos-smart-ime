## Context

The repository already proved the following:

- `SmartIMEHost` builds as a real InputMethodKit app bundle
- the installed bundle registers as `TISTypeKeyboardInputMethodWithoutModes`
- `TISCreateInputSourceList` reports the source as `ENABLED=1` and `SELECTABLE=1`

The remaining issue is display and switchability. The IME can appear in System Settings but still fail to show in the menu bar input switcher or the keyboard shortcut cycle. Local inspection on this machine showed a malformed `AppleEnabledInputSources` entry with `InputSourceKind = "Keyboard Input Method"` but no `Bundle ID`, while the working third-party reference input method (`hallelujahIM`) presents a more complete display-metadata shape.

## Goals / Non-Goals

**Goals**

- Make `SmartIMEHost` visible in the menu bar switcher and keyboard cycling flow after repository-owned installation
- Preserve the current no-modes registration model
- Repair common local preference corruption in `AppleEnabledInputSources` without asking future agents to manually edit plist state
- Keep the change local-first and deterministic

**Non-Goals**

- Add new typing features
- Change the `InputMethodKit` runtime architecture
- Introduce a nib-based UI or other unrelated app-shell changes
- Rewrite all input-source preferences from scratch beyond what is needed to repair malformed entries and ensure `SmartIMEHost` is enabled

## Decisions

### Add explicit display metadata and localized display resources

`SmartIMEHost` should expose a stable UI-facing name through both `CFBundleDisplayName` and localized `InfoPlist.strings` files. The bundle should also explicitly declare `tsInputMethodLanguageKey` in addition to the existing intended-language and repertoire keys.

This follows the working reference direction from `hallelujahIM` while staying within the current app-shell structure.

Alternative considered:

- Only add `CFBundleDisplayName`
  - Rejected because the current issue is specifically in UI presentation and localized display resources are low-cost and higher-confidence.

### Repair `AppleEnabledInputSources` during installation

The install workflow should inspect the current user's `com.apple.HIToolbox` preferences, remove malformed `Keyboard Input Method` items that lack `Bundle ID`, de-duplicate any stale `SmartIMEHost` entries, and ensure a valid `SmartIMEHost` entry exists in both `AppleEnabledInputSources` and `AppleInputSourceHistory`.

Alternative considered:

- Keep preference cleanup manual
  - Rejected because the repository already owns installation scripts, and this corruption is now a known local blocker.

### Keep enablement targeted to the logged-in user

Even when the app is installed system-wide under `/Library/Input Methods/`, the preference repair and enablement should target the logged-in user rather than root. This avoids writing `com.apple.HIToolbox` state into the wrong home directory.

Alternative considered:

- Run all post-install registration as root
  - Rejected because the switcher state is user-scoped.

### Keep the current registration model

The bundle should remain `TISTypeKeyboardInputMethodWithoutModes`. The issue is now with visibility, not with top-level source selectability, and the current type already matches a working third-party reference.

Alternative considered:

- Reintroduce `ComponentInputModeDict`
  - Rejected because that previously produced a non-selectable top-level source and made the UX worse.

## Proposed Implementation

### Bundle metadata and resources

Update `apps/ime/Resources/Info.plist`:

- add `CFBundleDisplayName`
- add `tsInputMethodLanguageKey`

Add localized resources:

- `apps/ime/Resources/en.lproj/InfoPlist.strings`
- `apps/ime/Resources/zh-Hans.lproj/InfoPlist.strings`

These files should define a stable UI-facing display name of `SmartIMEHost`.

### Install workflow repair

Extend `scripts/ime/install-host.sh` to:

1. install and register the app as before
2. determine the target logged-in user for HIToolbox preference updates
3. export `com.apple.HIToolbox`
4. repair `AppleEnabledInputSources` by:
   - removing malformed `Keyboard Input Method` items without `Bundle ID`
   - removing duplicate `SmartIMEHost` items
   - appending a single valid `SmartIMEHost` keyboard-input-method entry
5. ensure `AppleInputSourceHistory` also contains a valid `SmartIMEHost` entry
6. import the repaired plist back into the target user's preferences
7. call `TISEnableInputSource` for `SmartIMEHost`
8. refresh `TextInputMenuAgent` and `SystemUIServer`

The script should keep the current app-copy and ownership logic unchanged.

### Documentation

Update the manual validation document so it distinguishes:

- visible in System Settings
- visible in menu bar switcher
- reachable through keyboard input-source cycling

Record the fix and rationale in `docs/implementation-log.md`.

## Risks / Trade-offs

- [Preference repair may touch unrelated user input-source ordering] -> The repair is intentionally narrow: remove malformed keyboard-input-method entries lacking `Bundle ID`, dedupe only `SmartIMEHost`, and otherwise preserve the list order.
- [Localized display resources may still not fully satisfy macOS UI caching] -> The install flow still refreshes the relevant agents; if the issue persists, the next escalation would be logout/login rather than further bundle-shape speculation.
- [Running user-scoped preference repair from a system install path can target the wrong account] -> Resolve the target user explicitly from `SUDO_USER` or the current user.

## Migration Plan

1. Add bundle display metadata and localization resources.
2. Extend the install script with HIToolbox repair and source enablement.
3. Rebuild and reinstall `SmartIMEHost`.
4. Verify the switcher-visible path:
   - System Settings
   - menu bar switcher
   - input-source keyboard cycling
5. Record the implementation result and any remaining gaps.
